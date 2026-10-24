import SwiftUI
import SwiftData

/// The shopping tab: set a budget, fill the gaps in a room, and search for
/// pieces that fit.
struct CatalogView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Room.updatedAt, order: .reverse) private var rooms: [Room]
    @Query(sort: \Product.fetchedAt, order: .reverse) private var wishlist: [Product]

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue
    @AppStorage(SettingsKey.defaultBudget) private var defaultBudget: Double?
    @AppStorage(SettingsKey.preferredStyles) private var stylesCSV = ""
    @AppStorage(SettingsKey.preferredMaterials) private var materialsCSV = ""
    @AppStorage(SettingsKey.minimumRating) private var minimumRating: Double = 0

    @State private var store = CatalogStore()
    @State private var query = CatalogQuery()
    @State private var searchText = ""
    @State private var selectedRoomID: UUID?
    @State private var showFilters = false
    @State private var showBudget = false
    @State private var showWishlist = false

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    private var room: Room? { rooms.first { $0.uuid == selectedRoomID } ?? rooms.first }

    private var budget: ShoppingBudget {
        let prefs = room?.preferences
        var perItem: [ItemType: Double] = [:]
        for cap in prefs?.perItemBudgets ?? [] { perItem[cap.type] = cap.amount }
        return ShoppingBudget(
            total: prefs?.totalBudget ?? defaultBudget,
            perItem: perItem,
            committed: wishlist.map(\.price).reduce(0, +)
        )
    }

    private var preferences: ShoppingPreferences {
        func set(_ csv: String) -> Set<String> { Set(csv.split(separator: ",").map(String.init)) }
        return ShoppingPreferences(styles: set(stylesCSV), materials: set(materialsCSV), minRating: minimumRating)
    }

    private var snapshot: CatalogStore.RoomSnapshot? {
        room.map { CatalogStore.RoomSnapshot(room: $0.layoutRoom, items: $0.layoutItems, hasChosenLayout: $0.chosenLayout != nil) }
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    budgetCard

                    if store.source == .curated {
                        Label("Showing sample products. The live catalog isn't connected yet.", systemImage: "info.circle")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if !store.gaps.isEmpty {
                        gapsSection
                    }

                    searchBar

                    if store.isLoading && store.results.isEmpty {
                        // Grey placeholder cards while searching.
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(0..<4, id: \.self) { _ in
                                ProductCard(product: .placeholder, fit: nil, unit: unit)
                            }
                        }
                        .redacted(reason: .placeholder)
                        .accessibilityLabel("Loading products")
                    } else if store.results.isEmpty {
                        Text("Nothing matches. Try fewer filters or a bigger budget.")
                            .font(Typography.body)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        if let note = store.fitNote {
                            Text(note)
                                .font(Typography.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(store.results) { product in
                                NavigationLink {
                                    ProductDetailView(product: product, fit: store.fit[product.id], room: room)
                                } label: {
                                    ProductCard(product: product, fit: store.fit[product.id], unit: unit)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }

                    AffiliateDisclosure()
                }
                .padding(Theme.Space.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Catalog")
            .toolbar {
                // Left to right: wishlist, profile (profile stays far right).
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ToolbarIconButton(systemName: wishlist.isEmpty ? "heart" : "heart.fill", label: "Wishlist") {
                        showWishlist = true
                    }
                    ProfileButton()
                }
            }
            .sheet(isPresented: $showFilters) { CatalogFiltersSheet(query: $query) }
            .sheet(isPresented: $showBudget) {
                if let room { BudgetSheet(room: room) }
            }
            .navigationDestination(isPresented: $showWishlist) { WishlistView(room: room) }
            .task(id: searchKey) {
                await store.search(query, budget: budget, preferences: preferences, room: snapshot)
            }
            .task(id: gapsKey) {
                guard let room else { store.gaps = []; return }
                await store.fillGaps(MissingPieces.suggest(for: room.layoutItems), budget: budget, preferences: preferences, room: snapshot)
            }
        }
    }

    /// Re-search when any of these change.
    private var searchKey: String {
        "\(query.hashValue)|\(budget.total ?? -1)|\(budget.committed)|\(room?.layoutSignature ?? "")|\(stylesCSV)|\(materialsCSV)"
    }

    private var gapsKey: String {
        "\(room?.layoutSignature ?? "")|\(budget.total ?? -1)|\(budget.committed)"
    }

    // MARK: Budget

    private var budgetCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    if rooms.count > 1, let room {
                        Menu {
                            ForEach(rooms) { option in
                                Button(option.name) { selectedRoomID = option.uuid }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(room.name)
                                Image(systemName: "chevron.down").font(.caption)
                            }
                            .font(Typography.headline)
                            .foregroundStyle(Theme.textPrimary)
                        }
                    } else {
                        Text(room?.name ?? "Shopping")
                            .font(Typography.headline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    Button("Edit budget") { showBudget = true }
                        .font(Typography.subheadline)
                        .frame(minHeight: Theme.minTap)
                        .disabled(room == nil)
                }
                if let total = budget.total {
                    Text("\(money(budget.remaining ?? 0)) left of \(money(total))")
                        .font(Typography.title)
                        .foregroundStyle(Theme.textPrimary)
                    if budget.committed > 0 {
                        Text("\(money(budget.committed)) is on your wishlist.")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    Text("Set a budget to see only what you can afford.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: Fill the gaps

    private var gapsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: "Fill the gaps")
            ForEach(store.gaps) { gap in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(gap.piece.name) · \(gap.piece.reason)")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if gap.products.isEmpty {
                        Text("Nothing in the catalog fits here within budget yet.")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.vertical, 4)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(gap.products) { product in
                                    NavigationLink {
                                        ProductDetailView(product: product, fit: store.fit[product.id], room: room)
                                    } label: {
                                        ProductCard(product: product, fit: store.fit[product.id], unit: unit)
                                            .frame(width: 170)
                                    }
                                    .buttonStyle(PressableStyle())
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: Theme.Space.sm) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Search, like \"oak coffee table\"", text: $searchText)
                    .submitLabel(.search)
                    .onSubmit { query.text = searchText }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))

            IconButton(systemName: activeFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle", label: "Filters") {
                showFilters = true
            }
        }
    }

    private var activeFilters: Bool {
        query.type != nil || query.minPrice != nil || query.maxPrice != nil || query.minRating > 0
            || !query.materials.isEmpty || !query.styles.isEmpty || !query.colors.isEmpty
    }
}

/// Shown near every shopping link, as the affiliate programs and the App
/// Store expect.
struct AffiliateDisclosure: View {
    var body: some View {
        Label("We may earn a commission when you buy through links in the app. It doesn't change the price you pay.", systemImage: "info.circle")
            .font(Typography.caption)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

func money(_ amount: Double, currency: String = Locale.current.currency?.identifier ?? "USD") -> String {
    amount.formatted(.currency(code: currency).precision(.fractionLength(0)))
}
