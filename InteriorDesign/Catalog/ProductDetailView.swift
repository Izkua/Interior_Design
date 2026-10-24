import SwiftUI
import SwiftData
import SafariServices

/// One product: photo, price, size, whether it fits and why, a link to
/// the retailer, save to wishlist, and a preview in the room's layout.
struct ProductDetailView: View {
    let product: CatalogProduct
    let fit: FitResult?
    let room: Room?

    @Environment(\.modelContext) private var context
    @Query private var saved: [Product]

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue

    @State private var showRetailer = false
    /// The buy link to open: fetched fresh, or the saved one as a fallback.
    @State private var retailerURL: URL?
    @State private var isOpening = false
    @State private var freshPrice: Double?
    /// Worked out here when the screen was opened without one.
    @State private var checkedFit: FitResult?
    /// Where the room's furniture stands, ready for the preview screen.
    @State private var preview: PreviewTarget?

    struct PreviewTarget: Hashable {
        var furniture: [ItemPlacement]
        var item: LayoutItem
        var placement: ItemPlacement
        static func == (a: Self, b: Self) -> Bool { a.placement == b.placement && a.furniture == b.furniture }
        func hash(into hasher: inout Hasher) { hasher.combine(placement.x); hasher.combine(placement.y) }
    }

    private var fitResult: FitResult? { fit ?? checkedFit }

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    init(product: CatalogProduct, fit: FitResult?, room: Room?) {
        self.product = product
        self.fit = fit
        self.room = room
        let id = product.id
        _saved = Query(filter: #Predicate<Product> { $0.externalID == id })
    }

    private var isSaved: Bool { !saved.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                ProductImage(product: product)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(product.retailer)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(product.name)
                        .font(Typography.title)
                        .foregroundStyle(Theme.textPrimary)
                    HStack {
                        Text(money(product.price, currency: product.currency))
                            .font(Typography.headline)
                        if let rating = product.rating {
                            Text("★ \(String(format: "%.1f", rating))" + (product.reviewCount.map { " (\($0) reviews)" } ?? ""))
                                .font(Typography.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                fitCard

                if !product.materials.isEmpty || !product.styles.isEmpty {
                    Text((product.materials + product.styles).joined(separator: " · "))
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                if let room, case .fits(let spot) = fitResult, let item = product.asLayoutItem(id: previewID) {
                    Button {
                        Task { await openPreview(room: room, item: item, spot: spot) }
                    } label: {
                        Label("Preview in \(room.name)", systemImage: "square.split.2x2")
                            .font(Typography.headline)
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }

                if product.url != nil {
                    PrimaryButton(title: isOpening ? "Opening…" : "View at \(product.retailer)", systemImage: "arrow.up.right.square") {
                        Task { await openRetailer() }
                    }
                    .disabled(isOpening)
                    .sheet(isPresented: $showRetailer) {
                        if let retailerURL { SafariView(url: retailerURL).ignoresSafeArea() }
                    }
                    if let freshPrice, abs(freshPrice - product.price) >= 1 {
                        Text("The price is now \(money(freshPrice, currency: product.currency)).")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else if product.isSample {
                    Text("This is a sample product to show how the catalog works. It isn't for sale.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                AffiliateDisclosure()
            }
            .padding(Theme.Space.md)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $preview) { target in
            if let room {
                LayoutDetailView(room: room, furniture: target.furniture, preview: (target.item, target.placement))
            }
        }
        .task {
            // Opened from the wishlist: check the fit in the background.
            guard fit == nil, let room else { return }
            let snapshot = CatalogStore.RoomSnapshot(room: room.layoutRoom, items: room.layoutItems, hasChosenLayout: room.chosenLayout != nil)
            let product = self.product
            checkedFit = await Task.detached { CatalogStore.fitResults(for: [product], in: snapshot).results[product.id] }.value
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ToolbarIconButton(systemName: isSaved ? "heart.fill" : "heart", label: isSaved ? "Remove from wishlist" : "Save to wishlist") {
                    toggleSaved()
                }
                ProfileButton()
            }
        }
    }

    /// A stable ID for the product while it's previewed in the layout.
    private var previewID: UUID {
        UUID(uuidString: product.id) ?? UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    }

    private var fitCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                FitBadge(fit: fitResult)
                if let w = product.widthCm, let d = product.depthCm, let h = product.heightCm, product.hasDimensions {
                    Text("\(Length.formatDimensions(width: w, depth: d, height: h, system: unit)) (W × D × H)")
                        .font(Typography.body)
                        .foregroundStyle(Theme.textPrimary)
                }
                switch fitResult {
                case .fits:
                    Text("There's a spot for it in \(room?.name ?? "your room") that keeps doors and walkways clear.")
                case .doesNotFit(let reason):
                    Text(reason)
                case .unknownSize:
                    Text("The retailer doesn't list its size, so we can't check it. Measure your space before buying.")
                case .none:
                    Text("Add a room to check whether it fits.")
                }
            }
            .font(Typography.caption)
            .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Places the room's furniture (in the background), then opens the
    /// preview.
    private func openPreview(room: Room, item: LayoutItem, spot: ItemPlacement) async {
        let snapshot = CatalogStore.RoomSnapshot(room: room.layoutRoom, items: room.layoutItems, hasChosenLayout: room.chosenLayout != nil)
        let furniture = await Task.detached { CatalogStore.furniturePlacements(snapshot).map(\.placement) }.value
        preview = PreviewTarget(
            furniture: furniture,
            item: item,
            placement: ItemPlacement(itemID: item.id, x: spot.x, y: spot.y, rotation: spot.rotation)
        )
    }

    /// Gets a fresh buy link (they expire) and today's price, then opens the
    /// retailer. If that fails, the link we already have is used.
    private func openRetailer() async {
        isOpening = true
        defer { isOpening = false }
        if !product.isSample,
           let fresh = try? await BackendCatalogService(accessToken: { await AuthStore.shared.validAccessToken() }).freshProduct(id: product.id) {
            retailerURL = fresh.url ?? product.url
            freshPrice = fresh.price
        } else {
            retailerURL = product.url
        }
        showRetailer = retailerURL != nil
    }

    private func toggleSaved() {
        if let existing = saved.first {
            context.delete(existing)
        } else {
            context.insert(Product(product))
        }
        try? context.save()
    }
}

/// The retailer's page, inside the app.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
