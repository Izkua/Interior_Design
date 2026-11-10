import SwiftUI

/// Every catalog product with a saved AI 3D model. Tap one to see it in
/// your room again (free: the model is already on the phone).
struct SavedModelsView: View {
    @State private var models = SavedModels.shared
    @State private var showing: ARPiece?
    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    var body: some View {
        Group {
            if models.entries.isEmpty {
                EmptyState(
                    systemImage: "cube",
                    title: "No 3D models yet",
                    message: "Open a product and tap \"See it in my room\". Its 3D model is saved here."
                )
            } else {
                List {
                    Section {
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
                    } footer: {
                        Text("AI-generated 3D, approximate. Swipe left to remove one from this phone.")
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
