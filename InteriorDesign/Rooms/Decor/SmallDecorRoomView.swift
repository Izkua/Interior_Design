import SwiftUI
import SwiftData

/// A room's "Small decor" page: the furniture, greyed out and fixed, and
/// the small decor on top, which can be dragged. Drop a piece on a desk,
/// table, dresser, shelf, or TV stand and it sits on it; anywhere else it
/// stands on the floor.
struct SmallDecorRoomView: View {
    @Bindable var room: Room

    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue
    @State private var placed: [PlacedItem] = []
    @State private var dragging: (id: UUID, point: CGPoint)?
    @State private var selectedID: UUID?
    @State private var showAdd = false
    @State private var editing: Item?
    /// A short note after Place, when it couldn't use the usual spot.
    @State private var notice: String?

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    var body: some View {
        let pieces = room.items(in: .smallDecor)
        VStack(spacing: 0) {
            AppCard(padding: 0) {
                GeometryReader { geo in
                    let layoutRoom = room.layoutRoom
                    let space = CanvasSpace(corners: layoutRoom.corners, size: geo.size, padding: LayoutPlanView.padding)
                    ZStack(alignment: .topLeading) {
                        // The furniture, greyed out: it can't be moved here.
                        LayoutPlanView(room: layoutRoom, placed: placed, unit: unit, showWallLengths: false, space: space)
                            .saturation(0)
                            .opacity(0.45)
                            .allowsHitTesting(false)
                        ForEach(pieces) { item in
                            if let spot = room.surfaceDecor.first(where: { $0.itemID == item.uuid }) {
                                marker(item, at: position(of: spot, item: item, space: space), space: space)
                            }
                        }
                    }
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .padding(.horizontal, Theme.Space.md)

            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    if room.chosenLayout == nil, !placed.isEmpty {
                        Text("Furniture is shown in the top suggested layout. Choose a layout on the Furniture page to use your own.")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: Theme.Space.sm) {
                        PrimaryButton(title: "Add", systemImage: "plus") { showAdd = true }
                        NavigationLink {
                            RecommendedLayoutsView(initialRoomID: room.uuid, kind: .smallDecor)
                        } label: {
                            Label("Ideas", systemImage: "sparkles")
                                .font(Typography.headline)
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    if let notice {
                        Label(notice, systemImage: "info.circle")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if pieces.isEmpty {
                        Text("Add plants, books, table lamps, monitors, clocks, or desk storage, then drag them onto your furniture.")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        listCard(pieces)
                    }
                }
                .padding(Theme.Space.md)
            }
        }
        .padding(.top, Theme.Space.sm)
        .task(id: room.layoutSignature) { placed = await placedFurniture(room) }
        .sheet(isPresented: $showAdd) { CaptureFlowView(defaultRoom: room) }
        .sheet(item: $editing) { ItemEditorSheet(item: $0) }
    }

    // MARK: Pieces on the plan

    private func marker(_ item: Item, at point: CGPoint, space: CanvasSpace) -> some View {
        let isDragging = dragging?.id == item.uuid
        let selected = selectedID == item.uuid
        let w = max(CGFloat(item.widthCm) * space.scale, 24)
        let h = max(CGFloat(item.depthCm) * space.scale, 24)
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.accent.opacity(selected || isDragging ? 0.9 : 0.75))
            Image(systemName: item.type.symbol)
                .font(.system(size: min(w, h) * 0.5, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
        }
        .frame(width: w, height: h)
        .shadow(color: .black.opacity(isDragging ? 0.3 : 0.15), radius: isDragging ? 6 : 2)
        .frame(width: max(w, Theme.minTap), height: max(h, Theme.minTap))
        .contentShape(Rectangle())
        .position(isDragging ? dragging!.point : point)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    selectedID = item.uuid
                    dragging = (item.uuid, CGPoint(x: point.x + value.translation.width, y: point.y + value.translation.height))
                }
                .onEnded { value in
                    let end = CGPoint(x: point.x + value.translation.width, y: point.y + value.translation.height)
                    drop(item, at: space.roomPoint(end))
                    dragging = nil
                }
        )
        .onTapGesture { selectedID = item.uuid }
        .accessibilityElement()
        .accessibilityLabel("\(item.name), \(whereText(item))")
        .accessibilityHint("Drag onto a piece of furniture to put it there")
    }

    /// Where a piece is drawn: on its furniture, or where it stands on the floor.
    private func position(of spot: SurfaceSpot, item: Item, space: CanvasSpace) -> CGPoint {
        if let hostID = spot.hostID, let host = placed.first(where: { $0.item.id == hostID }) {
            return space.viewPoint(SurfacePlacement.point(offset: spot.offsetCm, on: host))
        }
        if let x = spot.floorX, let y = spot.floorY {
            return space.viewPoint(Point2D(x: x, y: y))
        }
        // On the floor with no spot yet: by the room's middle.
        return space.viewPoint(room.layoutRoom.centroid)
    }

    /// Puts the piece on whatever furniture top is under the finger, or on
    /// the floor there.
    private func drop(_ item: Item, at p: Point2D) {
        var spots = room.surfaceDecor
        let index = spots.firstIndex { $0.itemID == item.uuid }
        var spot = index.map { spots[$0] } ?? SurfaceSpot(itemID: item.uuid, hostID: nil, offsetCm: 0)
        let host = placed.first { h in
            guard h.item.type.hasSurface else { return false }
            let box = h.footprint.expanded(by: 5)
            return p.x >= box.minX && p.x <= box.maxX && p.y >= box.minY && p.y <= box.maxY
        }
        if let host {
            spot.hostID = host.item.id
            spot.offsetCm = SurfacePlacement.offset(of: p, on: host, pieceWidth: item.widthCm)
            spot.floorX = nil
            spot.floorY = nil
        } else {
            spot.hostID = nil
            spot.floorX = p.x
            spot.floorY = p.y
        }
        if let index { spots[index] = spot } else { spots.append(spot) }
        room.applySurfaceDecor(spots)
        try? context.save()
    }

    // MARK: List

    private func listCard(_ pieces: [Item]) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Your small decor")
                ForEach(pieces) { item in
                    let isPlaced = room.surfaceDecor.contains { $0.itemID == item.uuid }
                    HStack(spacing: Theme.Space.sm + 4) {
                        Image(systemName: item.type.symbol)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(Typography.body)
                                .foregroundStyle(Theme.textPrimary)
                            Text(whereText(item))
                                .font(Typography.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if isPlaced {
                            Button("Edit") { editing = item }
                                .font(Typography.subheadline)
                                .frame(minHeight: Theme.minTap)
                        } else {
                            Button("Place") { notice = nil; autoPlace(item) }
                                .font(Typography.subheadline.weight(.semibold))
                                .frame(minHeight: Theme.minTap)
                        }
                    }
                    .frame(minHeight: Theme.minTap)
                    // The highlight runs edge to edge across the card.
                    .padding(.horizontal, Theme.Space.md)
                    .background(selectedID == item.uuid ? Theme.accent.opacity(0.12) : .clear)
                    .padding(.horizontal, -Theme.Space.md)
                }
            }
        }
    }

    private func whereText(_ item: Item) -> String {
        guard let spot = room.surfaceDecor.first(where: { $0.itemID == item.uuid }) else { return "Not placed yet" }
        if let hostID = spot.hostID, let host = placed.first(where: { $0.item.id == hostID }) {
            return "On the \(host.item.name.lowercased())"
        }
        return "On the floor"
    }

    /// Puts a piece where it works best, using the decor planner.
    private func autoPlace(_ item: Item) {
        let pieces = room.smallDecorPieces.filter { $0.id == item.uuid }
        // Leave room for what's already on each surface.
        var surfaces = room.decorSurfaces
        let space = room.decorSpace
        for i in surfaces.indices { surfaces[i].width -= space.usedWidth[surfaces[i].id] ?? 0 }
        var placedSpot: SurfaceSpot
        if let spot = SmallDecorPlanner.suggest(pieces: pieces, surfaces: surfaces).first?.spots.first {
            placedSpot = spot
            if let hostID = spot.hostID, let used = space.usedWidth[hostID] {
                placedSpot.offsetCm += used + DecorSurface.gap
            }
        } else if let host = surfaces.filter({ $0.width - 2 * DecorSurface.margin >= item.widthCm })
                    .max(by: { $0.width < $1.width }) {
            // No surface that usually suits it (a monitor with no desk):
            // the roomiest top there is, and the person can drag it after.
            let used = space.usedWidth[host.id].map { $0 + DecorSurface.gap } ?? 0
            placedSpot = SurfaceSpot(itemID: item.uuid, hostID: host.id, offsetCm: used + DecorSurface.margin + item.widthCm / 2)
            notice = "There's no desk here, so it went on the \(host.name.lowercased()). Drag it wherever you like."
        } else {
            // Nothing to put it on: the middle of the floor, ready to drag.
            let middle = room.layoutRoom.centroid
            placedSpot = SurfaceSpot(itemID: item.uuid, hostID: nil, offsetCm: 0, floorX: middle.x, floorY: middle.y)
            notice = "No furniture top has room for it, so it's on the floor. Drag it onto something to place it."
        }
        selectedID = item.uuid
        var spots = room.surfaceDecor.filter { $0.itemID != item.uuid }
        spots.append(placedSpot)
        room.applySurfaceDecor(spots)
        try? context.save()
    }
}
