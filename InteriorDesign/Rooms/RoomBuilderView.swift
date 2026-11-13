import SwiftUI
import SwiftData

/// The room builder: draw any shape corner by corner and type measured
/// wall lengths, or scan the room. Place doors, windows, and outlets.
/// Changes save as you make them.
struct RoomBuilderView: View {
    @Bindable var room: Room

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue

    @State private var selectedFeatureID: UUID?
    @State private var showRename = false
    @State private var draftName = ""
    @State private var confirmDelete = false
    @State private var selectedWall: Int?
    @State private var showScan = false
    /// Undo and redo for the advanced builder. Kept only while this screen
    /// is open.
    @State private var history = EditHistory<RoomOutline>()
    /// "Room" (walls, doors, windows), "Furniture" (where things stand), or
    /// "Walls" (posters, frames, and shelves on each wall).
    @State private var page: RoomPage = .room
    /// The wall the Walls page opens on.
    @State private var wallsPageWall = 0

    enum RoomPage: String, CaseIterable, Identifiable {
        case room = "Room"
        case furniture = "Furniture"
        case walls = "Walls"
        case smallDecor = "Small decor"
        var id: String { rawValue }
    }

    @AppStorage(SettingsKey.lockAngles) private var lockAngles = false

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $page) {
                ForEach(RoomPage.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.sm)
            // Room below the switch, and drawn above the page, so content
            // scrolling up never clips its bottom edge or shadow.
            .padding(.bottom, Theme.Space.sm)
            .background(Theme.background)
            .zIndex(1)
            .accessibilityLabel("Show the room's outline, its furniture, the decor on its walls, or its small decor")

            switch page {
            case .room: roomPage
            case .furniture: RoomFurnitureView(room: room)
            case .walls: WallDecorView(room: room, initialWall: wallsPageWall)
            case .smallDecor: SmallDecorRoomView(room: room)
            }
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
        .sheet(isPresented: $showScan) {
            ScanRoomView { draft in
                recordForUndo()
                room.apply(draft)
                room.addScannedFurniture(draft.furniture, context: context)
                selectedWall = nil
            }
        }
        .onAppear {
            // Rooms made before Basic mode was removed open as a drawing
            // with the same corners. (Not counted as an edit.)
            if room.shape != .custom { room.shape = .custom }
        }
        .onDisappear {
            try? context.save()
        }
    }

    /// Walls, corners, doors, windows, and outlets (what this screen was
    /// before it had two pages).
    private var roomPage: some View {
        VStack(spacing: 0) {
            // The plan stays pinned at the top while the form scrolls below.
            AppCard(padding: 0) {
                VStack(spacing: 0) {
                    AdvancedRoomCanvas(
                        room: room,
                        selectedWall: $selectedWall,
                        selectedFeatureID: $selectedFeatureID,
                        unit: unit,
                        lockAngles: lockAngles,
                        willEdit: recordForUndo
                    )
                    .frame(height: 300)
                    .clipped()
                    Divider()
                    advancedControls
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.sm)

            if let wall = selectedWall, room.corners.indices.contains(wall) {
                // Right under the plan, so it's seen as soon as a wall is tapped.
                PrimaryButton(title: editWallTitle(wall), systemImage: "square.and.pencil", style: .tinted) {
                    wallsPageWall = wall
                    page = .walls
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.top, Theme.Space.sm)
                .accessibilityHint("Opens this wall's front view to hang and arrange decor")
            }

            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    modeCard
                    advancedCards
                    featuresCard
                }
                .padding(Theme.Space.md)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    /// "Edit top wall decor", or "Edit Wall 3 decor" for odd-shaped rooms.
    private func editWallTitle(_ wall: Int) -> String {
        let name = PlanGeometry.wallName(wall, cornerCount: room.corners.count)
        return "Edit " + (name.hasPrefix("Wall") ? name : name.lowercased()) + " decor"
    }

    // MARK: How to draw, and Scan

    private var modeCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                Text("Tap the plan to add a corner, drag a corner to move it, long-press to delete it. Tap a wall to type its length.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // LiDAR phones can scan now; others see why not and are
                // pointed back to the drawing tools.
                Chip(title: RoomPlanScan.isAvailable || ARMeasure.isAvailable ? "Scan room · Beta" : "Scan room · Coming soon", systemImage: "camera.viewfinder") { showScan = true }
                    .accessibilityHint("Makes a draft outline from a scan, for you to check")
            }
        }
    }

    // MARK: Advanced builder

    /// The row under the plan: Lock angles at the bottom left, undo and
    /// redo at the bottom right.
    private var advancedControls: some View {
        HStack(spacing: Theme.Space.sm) {
            Chip(title: "Lock angles", systemImage: lockAngles ? "lock.fill" : "lock.open", isSelected: lockAngles) {
                lockAngles.toggle()
            }
            .accessibilityHint("Snaps corners to 30, 45, 60, or 90 degrees while dragging")

            Spacer()

            IconButton(systemName: "arrow.uturn.backward", label: "Undo", action: undo)
                .disabled(!history.canUndo)
                .opacity(history.canUndo ? 1 : 0.4)
            IconButton(systemName: "arrow.uturn.forward", label: "Redo", action: redo)
                .disabled(!history.canRedo)
                .opacity(history.canRedo ? 1 : 0.4)
        }
        .padding(.horizontal, Theme.Space.sm + 4)
        .padding(.vertical, Theme.Space.sm)
    }

    @ViewBuilder
    private var advancedCards: some View {
        if !PolygonGeometry.isSimple(room.corners) {
            warningCard(
                title: "Two walls cross",
                message: "Drag a corner back so the walls don't cross, or tap Undo."
            )
        }

        if let check = room.closureCheck {
            mismatchCard(check)
        }

        if !room.uncertainWalls.isEmpty {
            warningCard(
                title: "Check the dashed walls",
                message: "The scan wasn't sure about \(room.uncertainWalls.count == 1 ? "1 wall" : "\(room.uncertainWalls.count) walls"). Tap a dashed wall to type its real length, or drag its corners."
            )
        }

        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                if let wall = selectedWall, room.corners.indices.contains(wall) {
                    wallEditor(wall)
                } else {
                    SectionHeader(title: "Walls")
                    Text("Tap a wall on the plan to type the length you measured.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Divider()
                HStack {
                    Text("\(room.corners.count) corners")
                    Spacer()
                    Text("Floor area \(Length.formatArea(room.area, system: unit))")
                }
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func wallEditor(_ wall: Int) -> some View {
        let measured = room.measuredLength(wall)
        let binding = Binding<Double>(
            // Read fresh each time, not the values captured above.
            get: { room.measuredLength(wall) ?? PlanGeometry.wallLength(wall, corners: room.corners) },
            set: { newLength in
                recordForUndo()
                room.setWallLength(wall, to: newLength)
            }
        )
        return VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
            HStack {
                SectionHeader(title: PlanGeometry.wallName(wall, cornerCount: room.corners.count))
                if measured != nil { Tag(text: "Measured") }
            }
            LengthField(
                title: "Length",
                cm: binding,
                unit: unit,
                range: 30...3000,
                updatesWhileTyping: false
            )
            .id(wall)
            Text("The wall's far corner moves to match. Tap Return when done.")
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Shown when the measured walls cannot all be true at once.
    private func mismatchCard(_ check: PolygonGeometry.ClosureCheck) -> some View {
        let wallName = PlanGeometry.wallName(check.wall, cornerCount: room.corners.count)
        let measured = room.measuredLength(check.wall) ?? PlanGeometry.wallLength(check.wall, corners: room.corners)
        let direction = check.difference > 0 ? "short" : "long"
        return AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                Label("Your measurements don't fit together", systemImage: "exclamationmark.triangle.fill")
                    .font(Typography.headline)
                    .foregroundStyle(Theme.danger)
                Text("The walls miss closing by \(Length.format(check.gap, system: unit)). \(wallName) is most likely \(Length.format(abs(check.difference), system: unit)) too \(direction): measured \(Length.format(measured, system: unit)), but the room needs \(Length.format(check.suggestedLength, system: unit)).")
                    .font(Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "Use \(Length.format(check.suggestedLength, system: unit)) for \(wallName.lowercased())") {
                    recordForUndo()
                    room.applyFix(check)
                }
                Text("Or re-measure that wall and type the new length.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func warningCard(title: String, message: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(Typography.headline)
                    .foregroundStyle(Theme.danger)
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Undo

    private func recordForUndo() {
        history.record(room.outline)
    }

    private func undo() {
        guard let previous = history.undo(current: room.outline) else { return }
        restore(previous)
    }

    private func redo() {
        guard let next = history.redo(current: room.outline) else { return }
        restore(next)
    }

    private func restore(_ outline: RoomOutline) {
        room.outline = outline
        if let wall = selectedWall, !outline.corners.indices.contains(wall) {
            selectedWall = nil
        }
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
