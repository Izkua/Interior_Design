import SwiftUI
import PhotosUI

/// The "Walls" page of a room: pick a wall, see it from the front, and
/// plan where posters, frames, mirrors, and shelves go.
struct WallDecorView: View {
    @Bindable var room: Room

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue
    @State private var wall: Int
    @State private var selectedID: UUID?
    @State private var showAdd = false
    /// Small copies of the pieces' photos, drawn on the wall.
    @State private var photos: [UUID: UIImage] = [:]

    init(room: Room, initialWall: Int = 0) {
        self.room = room
        _wall = State(initialValue: initialWall)
    }

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }
    private var wallCount: Int { room.corners.count }
    private var safeWall: Int { wallCount == 0 ? 0 : min(max(wall, 0), wallCount - 1) }

    var body: some View {
        let w = safeWall
        let decor = room.decor(onWall: w)
        let features = room.features(onWall: w)
        let furniture = room.furnitureAgainst(wall: w)
        let problems = Dictionary(uniqueKeysWithValues: decor.map {
            ($0.id, WallDecorGeometry.problems(for: $0, features: features, others: decor, ceiling: room.ceilingHeightCm))
        })

        VStack(spacing: 0) {
            wallPicker
                .padding(.bottom, Theme.Space.sm)

            // The wall stays pinned at the top while the details scroll.
            AppCard(padding: 0) {
                WallElevationView(
                    wallLength: room.wallLength(w),
                    ceiling: room.ceilingHeightCm,
                    features: features,
                    furniture: furniture,
                    decor: decor,
                    problemIDs: Set(problems.filter { !$0.value.isEmpty }.keys),
                    corners: room.corners,
                    wall: w,
                    unit: unit,
                    selectedID: $selectedID,
                    photos: photos
                ) { moved in
                    room.updateDecor(id: moved.id) { $0 = moved }
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .padding(.horizontal, Theme.Space.md)

            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    if let id = selectedID, let piece = decor.first(where: { $0.id == id }) {
                        DecorEditorCard(
                            room: room,
                            piece: piece,
                            furniture: furniture,
                            problems: problems[id] ?? [],
                            unit: unit,
                            onDone: { selectedID = nil },
                            onMovedWall: { newWall in
                                wall = newWall
                            }
                        )
                    } else {
                        wallCard(decor: decor)
                    }
                }
                .padding(Theme.Space.md)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        // Hung pieces show up in Current Items too.
        .onAppear { room.linkDecorItems() }
        .task(id: room.decorPhotoKey) { photos = room.decorPhotos() }
        .onChange(of: wall) { _, _ in
            if let id = selectedID, room.wallDecor.first(where: { $0.id == id })?.wall != safeWall {
                selectedID = nil
            }
        }
        .sheet(isPresented: $showAdd) {
            AddDecorSheet(owned: room.unhungWallDecor) { kind in
                let piece = room.addDecor(kind, wall: w)
                room.linkDecorItems()
                selectedID = piece.id
                showAdd = false
            } onHang: { item in
                let piece = room.hang(item, onWall: w)
                selectedID = piece.id
                showAdd = false
            }
            .presentationDetents(room.unhungWallDecor.isEmpty ? [.height(320)] : [.medium, .large])
        }
    }

    // MARK: Wall picker

    private var wallPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(0..<wallCount, id: \.self) { index in
                        Chip(
                            title: PlanGeometry.wallName(index, cornerCount: wallCount),
                            isSelected: index == safeWall
                        ) {
                            wall = index
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, Theme.Space.md)
            }
            // Opened from "Edit wall": show that wall's chip.
            .onAppear { proxy.scrollTo(safeWall, anchor: .center) }
        }
        .accessibilityLabel("Choose a wall")
    }

    // MARK: Nothing selected

    private func wallCard(decor: [WallDecor]) -> some View {
        VStack(spacing: Theme.Space.md) {
            PrimaryButton(title: "Add decor", systemImage: "plus") { showAdd = true }

            if !room.wallDecorForPlanning.isEmpty {
                NavigationLink {
                    RecommendedLayoutsView(initialRoomID: room.uuid, kind: .wallDecor)
                } label: {
                    Label("Decor layout ideas", systemImage: "sparkles")
                        .font(Typography.headline)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }

            if decor.isEmpty {
                Text("Add posters, frames, mirrors, or shelves, then drag them on the wall. They snap to eye level, the middle of the wall, the furniture below, and each other.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                AppCard {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(title: "On this wall")
                        ForEach(decor) { piece in
                            Button {
                                selectedID = piece.id
                            } label: {
                                HStack(spacing: Theme.Space.sm + 4) {
                                    Image(systemName: piece.kind.symbol)
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 28)
                                    Text(piece.name)
                                        .font(Typography.body)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text("\(Length.formatFurniture(piece.widthCm, system: unit)) × \(Length.formatFurniture(piece.heightCm, system: unit))")
                                        .font(Typography.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                .frame(minHeight: Theme.minTap)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                let art = decor.filter { $0.kind != .shelf && $0.kind != .tv }
                if art.count >= 2 {
                    PrimaryButton(title: "Line up at eye level", systemImage: "rectangle.split.3x1", style: .tinted) {
                        lineUp(art)
                    }
                }
            }

            ceilingCard
        }
    }

    /// Hangs the pieces side by side with even gaps, centered where the
    /// group already is, at eye level.
    private func lineUp(_ pieces: [WallDecor]) {
        let rects = pieces.map(\.rect)
        let middle = ((rects.map(\.minX).min() ?? 0) + (rects.map(\.maxX).max() ?? 0)) / 2
        let row = WallDecorGeometry.row(pieces, centerX: middle, centerY: WallDecorGeometry.eyeLevelCm)
        // If the row is wider than where it started, keep it on the wall.
        let length = room.wallLength(safeWall)
        let rowRects = row.map(\.rect)
        let shift: Double = {
            let left = rowRects.map(\.minX).min() ?? 0
            let right = rowRects.map(\.maxX).max() ?? 0
            if left < 0 { return -left }
            if right > length { return length - right }
            return 0
        }()
        room.replaceDecor(row.map { var d = $0; d.centerX += shift; return d })
    }

    private var ceilingCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                LengthField(
                    title: "Ceiling height (every wall in this room)",
                    cm: Binding(get: { room.ceilingHeightCm }, set: { room.setCeilingHeight($0) }),
                    unit: unit,
                    range: WallDecorGeometry.ceilingRange,
                    updatesWhileTyping: false
                )
                Text(tip)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension WallDecorView {
    /// Rules of thumb, in round numbers for each unit system.
    fileprivate var tip: String {
        let sizes = unit == .metric
            ? (middle: "145 cm", above: "20 cm", between: "5 to 10 cm")
            : (middle: "57″", above: "8″", between: "2 to 4″")
        return "Tip: hang art with its middle about \(sizes.middle) from the floor, about \(sizes.above) above a sofa or table, with \(sizes.between) between frames. Door and window heights are typical sizes, not measured."
    }
}

// MARK: - Editing one piece

private struct DecorEditorCard: View {
    let room: Room
    let piece: WallDecor
    let furniture: [WallFurniture]
    let problems: [String]
    let unit: UnitSystem
    let onDone: () -> Void
    let onMovedWall: (Int) -> Void

    @State private var confirmDelete = false
    @State private var showWalls = false
    @State private var photoSelection: PhotosPickerItem?

    private var wallLength: Double { room.wallLength(piece.wall) }

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack {
                    Image(systemName: piece.kind.symbol)
                        .foregroundStyle(Theme.accent)
                    TextField("Name", text: Binding(
                        get: { piece.name },
                        set: { name in room.updateDecor(id: piece.id) { $0.name = name } }
                    ))
                    .font(Typography.headline)
                    .submitLabel(.done)
                    Button("Done", action: onDone)
                        .font(Typography.headline)
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: Theme.minTap)
                }

                ForEach(problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.danger)
                }

                HStack(alignment: .top, spacing: Theme.Space.sm) {
                    sizeField("Width", \.widthCm, range: 1...max(wallLength, 1))
                    sizeField("Height", \.heightCm, range: 1...max(room.ceilingHeightCm, 1))
                    if piece.kind.showsDepth {
                        sizeField("Depth", \.depthCm, range: 1...100)
                    }
                }

                lookSection

                // Where to put the nail, roughly: measured from the floor
                // and from the wall's left corner.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top edge \(Length.formatFurniture(piece.rect.maxY, system: unit)) from the floor")
                    Text("Middle \(Length.formatFurniture(piece.centerY, system: unit)) up, \(Length.formatFurniture(piece.centerX, system: unit)) from the left corner")
                }
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)

                FlowLayout(spacing: Theme.Space.sm) {
                    Chip(title: "Eye level", systemImage: "eye") {
                        room.updateDecor(id: piece.id) { $0.centerY = WallDecorGeometry.eyeLevelCm }
                    }
                    Chip(title: "Center on wall", systemImage: "arrow.left.and.right") {
                        room.updateDecor(id: piece.id) { $0.centerX = wallLength / 2 }
                    }
                    ForEach(furniture) { item in
                        Chip(title: "Over \(item.name)", systemImage: "arrow.up.to.line") {
                            room.updateDecor(id: piece.id) {
                                $0 = WallDecorGeometry.centered($0, above: item, ceiling: room.ceilingHeightCm)
                            }
                        }
                    }
                }

                // Stacked, full width: Move to wall, then Remove under it.
                // A plain button opens the wall list (a Menu draws its own
                // background on top of ours, which looked doubled).
                VStack(spacing: Theme.Space.sm) {
                    if room.corners.count > 1 {
                        Button {
                            showWalls = true
                        } label: {
                            Label("Move to wall", systemImage: "arrow.turn.up.right")
                                .font(Typography.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                                .background(Theme.surfaceAlt, in: Capsule())
                        }
                        .buttonStyle(PressableStyle())
                    }

                    Button {
                        confirmDelete = true
                    } label: {
                        Label("Remove from wall", systemImage: "trash")
                            .font(Typography.subheadline)
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                            .background(Theme.danger.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .confirmationDialog("Move \(piece.name) to", isPresented: $showWalls, titleVisibility: .visible) {
            ForEach(0..<room.corners.count, id: \.self) { index in
                if index != piece.wall {
                    Button(PlanGeometry.wallName(index, cornerCount: room.corners.count)) {
                        room.updateDecor(id: piece.id) {
                            $0.wall = index
                            $0.centerX = room.wallLength(index) / 2
                        }
                        onMovedWall(index)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove \(piece.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                room.removeDecor(id: piece.id)
                onDone()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Optional: a photo of the piece (shown on the wall, colors read from
    /// it) or a few color picks, so layouts can match it with the room.
    private var lookSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Text("Colors")
                    .font(Typography.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Text("optional")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if piece.kind != .tv {
                    PhotosPicker(selection: $photoSelection, matching: .images) {
                        Label(room.decorPhoto(for: piece.id) == nil ? "Add photo" : "New photo", systemImage: "photo")
                            .font(Typography.subheadline)
                            .frame(minHeight: Theme.minTap)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // Colors read from the photo that aren't in the list.
                    ForEach(piece.colors.filter { hex in !DecorColorOption.all.contains { $0.hex == hex } }, id: \.self) { hex in
                        swatch(hex: hex, name: "From the photo")
                    }
                    ForEach(DecorColorOption.all, id: \.hex) { option in
                        swatch(hex: option.hex, name: option.name)
                    }
                }
                .padding(.vertical, 4)
            }
            Text(piece.colors.isEmpty
                 ? "Tap up to 3 main colors, or add a photo and they're picked for you. Helps layouts match it with your room."
                 : "Used to match it with your other pieces.")
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: photoSelection) { _, selection in
            guard let selection else { return }
            Task {
                if let data = try? await selection.loadTransferable(type: Data.self) {
                    room.setDecorPhoto(data, for: piece.id)
                }
                photoSelection = nil
            }
        }
    }

    private func swatch(hex: String, name: String) -> some View {
        let isOn = piece.colors.contains(hex)
        return Button {
            room.updateDecor(id: piece.id) { d in
                if let i = d.colors.firstIndex(of: hex) { d.colors.remove(at: i) }
                else if d.colors.count < 3 { d.colors.append(hex) }
            }
        } label: {
            Circle()
                .fill(Color(uiColor: (RGB(hex: hex) ?? RGB(r: 0.5, g: 0.5, b: 0.5)).uiColor))
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                .overlay(Circle().stroke(Theme.accent, lineWidth: isOn ? 3 : 0).padding(-4))
                .frame(width: Theme.minTap, height: Theme.minTap)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func sizeField(_ title: String, _ key: WritableKeyPath<WallDecor, Double>, range: ClosedRange<Double>) -> some View {
        LengthField(
            title: title,
            cm: Binding(
                get: { piece[keyPath: key] },
                set: { value in room.updateDecor(id: piece.id) { $0[keyPath: key] = value } }
            ),
            unit: unit,
            range: range,
            updatesWhileTyping: false,
            scale: .furniture
        )
        // A new piece gets fresh fields instead of keeping the last one's text.
        .id("\(piece.id)-\(title)")
    }
}

// MARK: - Adding a piece

private struct AddDecorSheet: View {
    /// Wall decor from Current Items that isn't hung yet.
    var owned: [Item] = []
    let onPick: (DecorKind) -> Void
    var onHang: (Item) -> Void = { _ in }

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: Theme.Space.sm)]

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Add to this wall")
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)
            if !owned.isEmpty {
                SectionHeader(title: "Yours, not hung yet")
                ForEach(owned) { item in
                    Button { onHang(item) } label: {
                        HStack(spacing: Theme.Space.sm + 4) {
                            Image(systemName: item.type.symbol)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 28)
                            Text(item.name)
                                .font(Typography.body)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Theme.accent)
                        }
                        .frame(minHeight: Theme.minTap)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                SectionHeader(title: "Something new")
            }
            LazyVGrid(columns: columns, spacing: Theme.Space.sm) {
                ForEach(DecorKind.allCases) { kind in
                    Button {
                        onPick(kind)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 22))
                                .foregroundStyle(Theme.accent)
                            Text(kind.title)
                                .font(Typography.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            Text("It starts at a typical size. Change it after. It's added to Current Items too.")
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(Theme.Space.lg)
        }
    }
}
