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
    @Query(sort: \Room.updatedAt, order: .reverse) private var rooms: [Room]
    /// The room last chosen for previews, remembered between products.
    @AppStorage("catalog.previewRoomID") private var previewRoomID = ""
    @State private var showRooms = false
    @State private var showAR = false
    /// The product photo, for the cutout and AI model.
    @State private var productPhoto: Data?
    /// The cutout the person chose, and the product's 3D model, both kept
    /// on the phone.
    @State private var cutoutData: Data?
    @State private var modelData: Data?

    /// The room the fit check and preview use: the one picked here last,
    /// else the Catalog's room, else the most recently edited.
    private var activeRoom: Room? {
        let id = RoomChoice.pick(rooms.map(\.uuid), saved: previewRoomID, fallback: room?.uuid)
        return rooms.first { $0.uuid == id }
    }
    /// Where the room's furniture stands, ready for the preview screen.
    @State private var preview: PreviewTarget?
    /// True while the room's furniture is being arranged for the preview.
    @State private var isPreparingPreview = false

    struct PreviewTarget: Hashable, Identifiable {
        var id: UUID { placement.itemID }
        var furniture: [ItemPlacement]
        var item: LayoutItem
        var placement: ItemPlacement
        static func == (a: Self, b: Self) -> Bool { a.placement == b.placement && a.furniture == b.furniture }
        func hash(into hasher: inout Hasher) { hasher.combine(placement.x); hasher.combine(placement.y) }
    }

    /// The Catalog's fit check is for its room; for another room it's
    /// worked out here.
    private var fitResult: FitResult? {
        activeRoom?.uuid == room?.uuid ? (fit ?? checkedFit) : checkedFit
    }

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    init(product: CatalogProduct, fit: FitResult?, room: Room?) {
        self.product = product
        self.fit = fit
        self.room = room
        let id = product.id
        _saved = Query(filter: #Predicate<Product> { $0.externalID == id })
    }

    private var isSaved: Bool { !saved.isEmpty }

    /// The product for the room view, with its model and chosen cutout.
    private var arPiece: ARPiece? {
        guard var piece = ARPiece(product: product) else { return nil }
        piece.modelData = modelData
        piece.cutoutData = cutoutData
        return piece
    }

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

                if rooms.isEmpty {
                    Button {
                        showRooms = true
                    } label: {
                        Label("Add a room to preview", systemImage: "square.dashed")
                            .font(Typography.headline)
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                } else if let room = activeRoom, case .fits(let spot) = fitResult, let item = product.asLayoutItem(id: previewID) {
                    Button {
                        Task { await openPreview(room: room, item: item, spot: spot) }
                    } label: {
                        Label(isPreparingPreview ? "Getting the room ready…" : "Preview in 2D \(room.name)", systemImage: "square.split.2x2")
                            .font(Typography.headline)
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(isPreparingPreview)
                }

                if product.hasDimensions {
                    Model3DSection(
                        name: product.type?.displayName ?? "piece",
                        photoData: productPhoto,
                        cutoutData: $cutoutData,
                        modelData: $modelData,
                        onNewModel: { SavedModels.shared.save(model: $0, for: product) },
                        isPaused: showAR
                    ) {
                        showAR = true
                    }
                }

                AffiliateDisclosure()
            }
            .padding(Theme.Space.md)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        // A sheet, not a pushed screen: on iOS 26, a navigationDestination
        // on this (already pushed) screen kept rebuilding the preview every
        // frame and froze the app.
        .fullScreenCover(isPresented: $showAR) {
            if let piece = arPiece { ARPlaceView(start: [piece]) }
        }
        .sheet(isPresented: $showRooms) {
            NavigationStack { RoomListView() }
        }
        .sheet(item: $preview) { target in
            if let room = activeRoom {
                NavigationStack {
                    LayoutDetailView(room: room, furniture: target.furniture, preview: (target.item, target.placement))
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") { preview = nil }
                                    .frame(minHeight: Theme.minTap)
                            }
                        }
                }
                // Dragging furniture shouldn't close the sheet.
                .interactiveDismissDisabled()
            }
        }
        .task {
            // The saved cutout and model on this phone, else a model someone
            // already made (free). Never makes a new one here.
            cutoutData = SavedModels.shared.cutout(product.id)
            modelData = SavedModels.shared.model(product.id)
            if let url = product.imageURL, let (data, _) = try? await URLSession.shared.data(from: url) {
                productPhoto = data
            }
            if modelData == nil, !product.isSample, let shared = await ProductModelService.savedModel(productID: product.id) {
                modelData = shared
                SavedModels.shared.save(model: shared, for: product)
            }
        }
        .onChange(of: cutoutData) { _, png in SavedModels.shared.setCutout(png, for: product.id) }
        .onChange(of: modelData) { _, data in
            if data == nil { SavedModels.shared.remove(product.id) }
        }
        .task(id: activeRoom?.uuid) {
            // Check the fit in the background when it isn't known yet: opened
            // from the wishlist, or a different room was picked here.
            guard let room = activeRoom, fit == nil || room.uuid != self.room?.uuid else { return }
            checkedFit = nil
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
                HStack {
                    FitBadge(fit: fitResult)
                    Spacer()
                    if rooms.count > 1, let current = activeRoom {
                        Menu {
                            ForEach(rooms) { option in
                                Button {
                                    previewRoomID = option.uuid.uuidString
                                } label: {
                                    if option.uuid == current.uuid {
                                        Label(option.name, systemImage: "checkmark")
                                    } else {
                                        Text(option.name)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(current.name).lineLimit(1)
                                Image(systemName: "chevron.down").font(.caption)
                            }
                            .font(Typography.subheadline)
                            .frame(minHeight: Theme.minTap)
                        }
                        .accessibilityLabel("Room: \(current.name). Choose another room to check and preview in.")
                    }
                }
                if let w = product.widthCm, let d = product.depthCm, let h = product.heightCm, product.hasDimensions {
                    Text("\(Length.formatDimensions(width: w, depth: d, height: h, system: unit)) (W × D × H)")
                        .font(Typography.body)
                        .foregroundStyle(Theme.textPrimary)
                }
                switch fitResult {
                case .fits:
                    Text("There's a spot for it in \(activeRoom?.name ?? "your room") that keeps doors and walkways clear.")
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
        guard !isPreparingPreview else { return }
        isPreparingPreview = true
        defer { isPreparingPreview = false }
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

/// Which room a product is checked against and previewed in.
enum RoomChoice {
    /// The saved choice if that room still exists, else the fallback (the
    /// Catalog's room) if it exists, else the first room (most recently
    /// edited). Nil with no rooms.
    static func pick(_ roomIDs: [UUID], saved: String, fallback: UUID?) -> UUID? {
        if let id = UUID(uuidString: saved), roomIDs.contains(id) { return id }
        if let fallback, roomIDs.contains(fallback) { return fallback }
        return roomIDs.first
    }
}

