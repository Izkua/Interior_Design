import SwiftUI
import SwiftData

/// Every 3D model on this phone: your own items' models and the catalog
/// products'. Tap one to see it in your room again (free: the model is
/// already on the phone).
struct SavedModelsView: View {
    @State private var models = SavedModels.shared
    @Query(filter: #Predicate<Item> { $0.modelData != nil }, sort: \Item.createdAt) private var items: [Item]
    @State private var showing: ARPiece?
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
                            Button {
                                var piece = ARPiece(product: entry.product)
                                piece?.modelData = models.model(entry.id)
                                piece?.cutoutData = models.cutout(entry.id)
                                showing = piece
                            } label: {
                                row(entry.product)
                            }
                            .disabled(!ARPlaceView.isAvailable)
                        }
                        .onDelete { offsets in
                            for index in offsets { models.remove(models.entries[index].id) }
                        }
                    }
                    }
                    Section {} footer: {
                        Text("AI-generated models are approximate. Swipe left on a catalog model to remove it from this phone; your items' models are removed from the item itself.")
                            .font(Typography.caption)
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
    }

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
                Text(Length.formatDimensions(width: item.widthCm, depth: item.depthCm, height: item.heightCm, system: unit))
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
                if let w = product.widthCm, let d = product.depthCm, let h = product.heightCm {
                    Text(Length.formatDimensions(width: w, depth: d, height: h, system: unit))
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
