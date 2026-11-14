import SwiftUI
import SwiftData

/// Every 3D model on this phone: your own items' models and the catalog
/// products'. Tap one to see it in your room again (free: the model is
/// already on the phone).
struct SavedModelsView: View {
    @State private var models = SavedModels.shared
    @Query(filter: #Predicate<Item> { $0.modelData != nil }, sort: \Item.createdAt) private var items: [Item]
    @State private var showing: ARPiece?
    @State private var storePage: StorePage?
    /// The product whose store link is being fetched.
    @State private var opening: String?
    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    var body: some View {
        Group {
            if models.entries.isEmpty && items.isEmpty {
                EmptyState(
                    systemImage: "cube",
                    title: "No 3D models yet",
                    message: "3D models you make or import for your items and catalog products are kept here."
                )
            } else {
                List {
                    if !items.isEmpty {
                        Section("Your items") {
                            ForEach(items) { item in
                                Button {
                                    showing = ARPiece(item: item)
                                } label: {
                                    itemRow(item)
                                }
                                .disabled(!ARPlaceView.isAvailable)
                            }
                        }
                    }
                    if !models.entries.isEmpty {
                    Section("Catalog") {
                        ForEach(models.entries) { entry in
                            HStack(spacing: Theme.Space.sm) {
                                Button {
                                    var piece = ARPiece(product: entry.product)
                                    piece?.modelData = models.model(entry.id)
                                    piece?.cutoutData = models.cutout(entry.id)
                                    showing = piece
                                } label: {
                                    row(entry.product)
                                }
                                .buttonStyle(.borderless)
                                .disabled(!ARPlaceView.isAvailable)
                                if entry.product.url != nil {
                                    Button {
                                        Task { await openProduct(entry.product) }
                                    } label: {
                                        Image(systemName: opening == entry.id ? "hourglass" : "arrow.up.right.square")
                                            .font(.system(size: 20))
                                            .foregroundStyle(Theme.accent)
                                            .frame(width: Theme.minTap, height: Theme.minTap)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Open \(entry.product.name) at \(entry.product.retailer)")
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { models.remove(models.entries[index].id) }
                        }
                    }
                    }
                    Section {} footer: {
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Text("Tap a model to see it in your room, or the arrow to open the product at the store. AI-generated models are approximate. Swipe left on a catalog model to remove it from this phone; your items' models are removed from the item itself.")
                                .font(Typography.caption)
                            if !models.entries.isEmpty { AffiliateDisclosure() }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("3D models")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }
        .fullScreenCover(item: $showing) { piece in
            ARPlaceView(start: [piece])
        }
        .sheet(item: $storePage) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
    }

    /// The store page, with a fresh buy link (they expire); the saved link
    /// is used if the fresh one can't be fetched.
    private func openProduct(_ product: CatalogProduct) async {
        opening = product.id
        defer { opening = nil }
        var url = product.url
        if !product.isSample,
           let fresh = try? await BackendCatalogService(accessToken: { await AuthStore.shared.validAccessToken() }).freshProduct(id: product.id) {
            url = fresh.url ?? url
        }
        if let url { storePage = StorePage(url: url) }
    }

    struct StorePage: Identifiable { let url: URL; var id: URL { url } }

    private func itemRow(_ item: Item) -> some View {
        HStack(spacing: Theme.Space.sm + 4) {
            ZStack {
                Theme.surfaceAlt
                if let data = item.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: item.type.symbol).foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(Typography.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(Length.formatDimensions(height: item.heightCm, width: item.widthCm, depth: item.depthCm, system: unit))
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "arkit")
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("See it in my room")
        }
        .frame(minHeight: Theme.minTap)
    }

    private func row(_ product: CatalogProduct) -> some View {
        HStack(spacing: Theme.Space.sm + 4) {
            ProductImage(product: product)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(Typography.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if let w = product.widthCm, let h = product.heightCm {
                    Text(Length.formatDimensions(height: h, width: w, depth: product.depthCm, system: unit))
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "arkit")
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("See it in my room")
        }
        .frame(minHeight: Theme.minTap)
    }
}
