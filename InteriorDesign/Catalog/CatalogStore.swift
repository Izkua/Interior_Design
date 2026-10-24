import Foundation
import Observation

/// One gap in a room and the best products to fill it.
struct GapSuggestion: Identifiable, Sendable {
    var piece: MissingPiece
    var products: [CatalogProduct]
    var id: String { piece.name }
}

/// What the Catalog tab shows, and the work behind it. Searching and fit
/// checks run off the main thread; results land back here.
@MainActor
@Observable
final class CatalogStore {
    var results: [CatalogProduct] = []
    var gaps: [GapSuggestion] = []
    var fit: [String: FitResult] = [:]
    var source: CatalogSource = .live
    var isLoading = false
    /// Explains what the fit badges were checked against.
    var fitNote: String?

    private let service: FallbackCatalogService

    init(service: FallbackCatalogService = FallbackCatalogService(
        primary: BackendCatalogService(accessToken: { await AuthStore.shared.validAccessToken() }),
        backup: CuratedCatalogService()
    )) {
        self.service = service
    }

    /// The room as the fit check needs it: its outline and where its
    /// furniture stands now.
    struct RoomSnapshot: Sendable {
        var room: LayoutRoom
        var items: [LayoutItem]
        var hasChosenLayout: Bool
    }

    func search(_ query: CatalogQuery, budget: ShoppingBudget, preferences: ShoppingPreferences, room: RoomSnapshot?) async {
        isLoading = true
        defer { isLoading = false }

        let (found, source) = await service.search(query)
        let filtered = CatalogRanking.filter(found, query: query, budget: budget)

        // Check every product against the room in the background.
        let fit = await Task.detached(priority: .userInitiated) {
            Self.fitResults(for: filtered, in: room)
        }.value

        self.source = source
        self.fit = self.fit.merging(fit.results) { _, new in new }
        self.fitNote = fit.note
        self.results = CatalogRanking.rank(filtered, preferences: preferences, budget: budget, fit: self.fit)
    }

    /// For each missing piece, the best few products that fit and stay
    /// within budget.
    func fillGaps(_ pieces: [MissingPiece], budget: ShoppingBudget, preferences: ShoppingPreferences, room: RoomSnapshot?) async {
        var found: [GapSuggestion] = []
        for piece in pieces {
            var query = CatalogQuery()
            query.type = piece.type
            query.minRating = preferences.minRating
            let (products, _) = await service.search(query)
            let affordable = CatalogRanking.filter(products, query: query, budget: budget)
            let fit = await Task.detached(priority: .userInitiated) {
                Self.fitResults(for: affordable, in: room)
            }.value
            self.fit = self.fit.merging(fit.results) { _, new in new }
            // Only products known to fit fill a gap.
            let ranked = CatalogRanking.rank(affordable, preferences: preferences, budget: budget, fit: fit.results)
                .filter { fit.results[$0.id]?.fits == true }
            found.append(GapSuggestion(piece: piece, products: Array(ranked.prefix(3))))
        }
        gaps = found
    }

    // MARK: Fit checks (run off the main thread)

    nonisolated static func fitResults(for products: [CatalogProduct], in snapshot: RoomSnapshot?) -> (results: [String: FitResult], note: String?) {
        guard let snapshot else {
            return ([:], "Add a room to check what fits.")
        }
        let furniture = furniturePlacements(snapshot)
        let note = snapshot.hasChosenLayout || snapshot.items.isEmpty
            ? nil
            : "Checked against the top suggested layout. Choose a layout for an exact check."
        var results: [String: FitResult] = [:]
        for product in products {
            results[product.id] = FitCheck.check(product, room: snapshot.room, furniture: furniture)
        }
        return (results, note)
    }

    /// Where the room's furniture stands: the chosen layout, or else the
    /// top suggestion, so fit checks are realistic either way. Can take a
    /// moment, so call it off the main thread.
    nonisolated static func furniturePlacements(_ snapshot: RoomSnapshot) -> [PlacedItem] {
        let byID = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
        let placements: [ItemPlacement]
        if snapshot.hasChosenLayout {
            placements = snapshot.items.compactMap(\.current)
        } else if snapshot.items.isEmpty {
            placements = []
        } else {
            placements = LayoutEngine.suggest(room: snapshot.room, items: snapshot.items).first?.placements ?? []
        }
        return placements.compactMap { p in byID[p.itemID].map { PlacedItem(item: $0, placement: p) } }
    }
}
