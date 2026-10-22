import SwiftUI
import SwiftData

/// The basic room builder: pick a shape, type the size, and place doors,
/// windows, and outlets. Changes save as you make them.
struct RoomBuilderView: View {
    @Bindable var room: Room

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue

    @State private var selectedFeatureID: UUID?
    @State private var showRename = false
    @State private var draftName = ""
    @State private var confirmDelete = false

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    /// About 3 feet to 98 feet.
    private let sizeRange: ClosedRange<Double> = 100...3000

    var body: some View {
        VStack(spacing: 0) {
            // The plan stays pinned at the top while the form scrolls below.
            AppCard(padding: 0) {
                RoomCanvasView(room: room, selectedFeatureID: $selectedFeatureID, unit: unit)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.sm)

            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    sizeCard
                    featuresCard
                }
                .padding(Theme.Space.md)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        draftName = room.name
                        showRename = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete room", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: Theme.minTap, height: Theme.minTap)
                }
                .foregroundStyle(Theme.textPrimary)
                .accessibilityLabel("Room options")

                ProfileButton()
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
        .alert("Rename room", isPresented: $showRename) {
            TextField("Room name", text: $draftName)
            Button("Save") { room.rename(draftName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this room?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete room", role: .destructive) { deleteRoom() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your items stay in Current Items.")
        }
        .onDisappear {
            try? context.save()
        }
    }

    // MARK: Shape and size

    private var sizeCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SectionHeader(title: "Shape")
                Picker("Shape", selection: shapeBinding) {
                    ForEach(RoomShape.allCases) { shape in
                        Text(shape.title).tag(shape)
                    }
                }
                .pickerStyle(.segmented)

                SectionHeader(title: "Size")
                if room.shape == .square {
                    LengthField(title: "Side", cm: sideBinding, unit: unit, range: sizeRange)
                } else {
                    HStack(alignment: .top, spacing: Theme.Space.sm + 4) {
                        LengthField(title: "Width", cm: widthBinding, unit: unit, range: sizeRange)
                        LengthField(title: "Length", cm: lengthBinding, unit: unit, range: sizeRange)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Units")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Picker("Units", selection: unitBinding) {
                        ForEach(UnitSystem.allCases) { system in
                            Text(system.title).tag(system)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var shapeBinding: Binding<RoomShape> {
        Binding(get: { room.shape }, set: { room.setShape($0) })
    }

    private var widthBinding: Binding<Double> {
        Binding(get: { room.width }, set: { room.resize(width: $0, length: room.length) })
    }

    private var lengthBinding: Binding<Double> {
        Binding(get: { room.length }, set: { room.resize(width: room.width, length: $0) })
    }

    private var sideBinding: Binding<Double> {
        Binding(get: { room.width }, set: { room.resize(width: $0, length: $0) })
    }

    private var unitBinding: Binding<UnitSystem> {
        Binding(get: { unit }, set: { unitRaw = $0.rawValue })
    }

    // MARK: Doors, windows, outlets

    private var featuresCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                SectionHeader(title: "Doors, windows & outlets")
                Text("Add one, then drag it on the plan to slide it along the walls.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)

                FlowLayout(spacing: Theme.Space.sm) {
                    ForEach(FeatureKind.allCases) { kind in
                        Chip(title: "Add \(kind.title.lowercased())", systemImage: kind.symbol) {
                            let feature = room.addFeature(kind)
                            selectedFeatureID = feature.id
                        }
                    }
                }

                if !room.features.isEmpty {
                    Divider()
                    ForEach(room.features) { feature in
                        FeatureRow(
                            feature: feature,
                            cornerCount: room.corners.count,
                            isSelected: feature.id == selectedFeatureID,
                            unit: unit,
                            onSelect: { selectedFeatureID = feature.id },
                            onDelete: {
                                if selectedFeatureID == feature.id { selectedFeatureID = nil }
                                room.removeFeature(id: feature.id)
                            }
                        )
                        if feature.id == selectedFeatureID {
                            featureEditor(feature)
                                .id(feature.id)
                        }
                    }
                }
            }
        }
    }

    /// Size and, for doors, which way it opens. Shown under the selected
    /// feature's row.
    private func featureEditor(_ feature: FixedFeature) -> some View {
        let wallLength = PlanGeometry.wallLength(feature.wall, corners: room.corners)
        let allowed = feature.kind.widthRange
        let upper = max(min(allowed.upperBound, wallLength), allowed.lowerBound)
        let widthBinding = Binding<Double>(
            get: { room.features.first { $0.id == feature.id }?.widthCm ?? feature.widthCm },
            set: { newWidth in room.updateFeature(id: feature.id) { $0.widthCm = newWidth } }
        )

        return VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
            LengthField(
                title: "\(feature.kind.title) width",
                cm: widthBinding,
                unit: unit,
                range: allowed.lowerBound...upper
            )

            if feature.kind == .door {
                HStack(spacing: Theme.Space.sm) {
                    Chip(title: "Flip hinge", systemImage: "arrow.left.and.right") {
                        room.updateFeature(id: feature.id) { $0.hingeAtStart.toggle() }
                    }
                    Chip(
                        title: feature.opensInward ? "Opens inward" : "Opens outward",
                        systemImage: "arrow.up.and.down"
                    ) {
                        room.updateFeature(id: feature.id) { $0.opensInward.toggle() }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: Delete

    private func deleteRoom() {
        let target = room
        dismiss()
        // Wait for the screen to finish closing so nothing reads a deleted room.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            context.delete(target)
            try? context.save()
        }
    }
}

private struct FeatureRow: View {
    let feature: FixedFeature
    let cornerCount: Int
    let isSelected: Bool
    let unit: UnitSystem
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.sm + 4) {
            Image(systemName: feature.kind.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.kind.title)
                    .font(Typography.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Text("\(PlanGeometry.wallName(feature.wall, cornerCount: cornerCount)) · \(Length.format(feature.offsetCm, system: unit)) from the corner")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)

            IconButton(
                systemName: "trash",
                label: "Delete \(feature.kind.title.lowercased())",
                action: onDelete
            )
        }
        .padding(8)
        .background(
            isSelected ? Theme.accent.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
