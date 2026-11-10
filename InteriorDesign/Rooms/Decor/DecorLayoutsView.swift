import SwiftUI
import SwiftData

/// Which kind of layout the Layouts tab shows.
enum LayoutKind: String, CaseIterable, Identifiable {
    case furniture = "Furniture"
    case wallDecor = "Wall decor"
    case smallDecor = "Small decor"
    var id: String { rawValue }
}

/// Where the room's furniture stands, for working out what's against each
/// wall and what has a top: the chosen layout, else the top suggestion.
/// Can take a moment, so it runs off the main thread.
private func placedFurniture(_ room: Room) async -> [PlacedItem] {
    let items = room.layoutItems
    if room.chosenLayout != nil { return RoomFurniture.placed(items) }
    guard !items.isEmpty else { return [] }
    let layoutRoom = room.layoutRoom
    return await Task.detached(priority: .userInitiated) {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let placements = LayoutEngine.suggest(room: layoutRoom, items: items).first?.placements ?? []
        return placements.compactMap { p in byID[p.itemID].map { PlacedItem(item: $0, placement: p) } }
    }.value
}

// MARK: - Wall decor

/// Suggested ways to hang the room's wall decor, each shown wall by wall.
struct WallDecorLayoutsView: View {
    let room: Room
    var onAddDecor: () -> Void = {}

    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue
    @State private var suggestions: [WallDecorSuggestion] = []
    @State private var walls: [PlannerWall] = []
    @State private var isWorking = true

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            if room.wallDecorForPlanning.isEmpty {
                emptyCard
            } else if isWorking && suggestions.isEmpty {
                ProgressView("Arranging your wall decor…")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Text(note)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(suggestions) { suggestion in
                    card(suggestion)
                }
            }
        }
        .task(id: room.decorSignature) { await generate() }
    }

    private var note: String {
        room.chosenLayout == nil
            ? "Based on the top furniture layout. Choose a furniture layout so the decor lines up with where things really are."
            : "Based on your chosen furniture layout."
    }

    private var emptyCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                Label("No wall decor in \(room.name) yet", systemImage: "photo.on.rectangle")
                    .font(Typography.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Add posters, frames, mirrors, or shelves you own, and ideas for hanging them will show up here.")
                    .font(Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "Add wall decor", systemImage: "plus", action: onAddDecor)
            }
        }
    }

    private func card(_ suggestion: WallDecorSuggestion) -> some View {
        let inUse = WallDecorPlanner.same(room.wallDecor, suggestion.decor)
        return AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                HStack {
                    Text(suggestion.label)
                        .font(Typography.title)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if inUse { Tag(text: "On your walls now") }
                }
                Text(suggestion.detail)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(suggestion.walls, id: \.self) { index in
                    if let wall = walls.first(where: { $0.index == index }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(wall.name)
                                .font(Typography.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            WallElevationView(
                                wallLength: wall.length,
                                ceiling: room.ceilingHeightCm,
                                features: room.features(onWall: index),
                                furniture: wall.furniture,
                                decor: suggestion.decor.filter { $0.wall == index },
                                problemIDs: [],
                                corners: room.corners,
                                wall: index,
                                unit: unit,
                                selectedID: .constant(nil),
                                onMove: { _ in }
                            )
                            .frame(height: 190)
                            .allowsHitTesting(false)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                        }
                    }
                }

                PrimaryButton(title: inUse ? "In use" : "Use this layout", systemImage: inUse ? "checkmark" : "rectangle.on.rectangle", style: inUse ? .tinted : .filled) {
                    room.applyWallDecor(suggestion.decor)
                    room.linkDecorItems()
                    try? context.save()
                }
                .disabled(inUse)
            }
        }
    }

    private func generate() async {
        let pieces = room.wallDecorForPlanning
        guard !pieces.isEmpty else { isWorking = false; suggestions = []; return }
        isWorking = true
        let placed = await placedFurniture(room)
        let plannerWalls = room.plannerWalls(placed: placed)
        var colors: [UUID: RGB] = [:]
        for item in room.items(in: .wallDecor) {
            item.refreshColor()
            if let color = item.mainColor { colors[item.uuid] = color }
        }
        walls = plannerWalls
        suggestions = WallDecorPlanner.suggest(walls: plannerWalls, pieces: pieces, ceiling: room.ceilingHeightCm, colors: colors)
        isWorking = false
    }
}

// MARK: - Small decor

/// Suggested spots for plants, lamps, books, and other small pieces on the
/// room's furniture.
struct SmallDecorLayoutsView: View {
    let room: Room
    var onAddDecor: () -> Void = {}

    @Environment(\.modelContext) private var context
    @State private var suggestions: [SmallDecorSuggestion] = []

    var body: some View {
        let pieces = room.items(in: .smallDecor)
        let surfaces = room.decorSurfaces
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            if pieces.isEmpty {
                message(
                    title: "No small decor in \(room.name) yet",
                    text: "Add plants, books, table lamps, monitors, clocks, or desk storage, and ideas for where they go will show up here.",
                    action: true
                )
            } else if surfaces.isEmpty {
                message(
                    title: "Nothing to put them on",
                    text: "Small decor goes on a desk, table, dresser, shelf, or TV stand. Add one of those to \(room.name) first.",
                    action: false
                )
            } else {
                ForEach(suggestions) { card($0, surfaces: surfaces) }
            }
        }
        .task(id: room.decorSignature) {
            suggestions = SmallDecorPlanner.suggest(pieces: room.smallDecorPieces, surfaces: room.decorSurfaces)
        }
    }

    private func message(title: String, text: String, action: Bool) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                Label(title, systemImage: "leaf")
                    .font(Typography.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(text)
                    .font(Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if action {
                    PrimaryButton(title: "Add small decor", systemImage: "plus", action: onAddDecor)
                }
            }
        }
    }

    private func card(_ suggestion: SmallDecorSuggestion, surfaces: [DecorSurface]) -> some View {
        let items = Dictionary(room.items(in: .smallDecor).map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        let inUse = SmallDecorPlanner.same(room.surfaceDecor, suggestion.spots)
            && room.surfaceDecor.count == suggestion.spots.count
        let floor = suggestion.spots.filter { $0.hostID == nil }.compactMap { items[$0.itemID]?.name }
        let leftOut = suggestion.leftOut.compactMap { items[$0]?.name }

        return AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                HStack {
                    Text(suggestion.label)
                        .font(Typography.title)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if inUse { Tag(text: "Your setup") }
                }
                Text(suggestion.detail)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(surfaces) { surface in
                    let spots = suggestion.spots.filter { $0.hostID == surface.id }
                    if !spots.isEmpty {
                        SurfaceSketch(surface: surface, spots: spots, items: items)
                    }
                }
                if !floor.isEmpty {
                    Label("On the floor: \(floor.formatted(.list(type: .and)))", systemImage: "leaf")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                if !leftOut.isEmpty {
                    Text("No room for: \(leftOut.formatted(.list(type: .and)))")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.danger)
                }

                PrimaryButton(title: inUse ? "In use" : "Use this setup", systemImage: inUse ? "checkmark" : "leaf", style: inUse ? .tinted : .filled) {
                    room.applySurfaceDecor(suggestion.spots)
                    try? context.save()
                }
                .disabled(inUse)
            }
        }
    }
}

/// A front view of one surface (desk, dresser, ...) with the small decor
/// standing on it, drawn to scale.
struct SurfaceSketch: View {
    let surface: DecorSurface
    let spots: [SurfaceSpot]
    let items: [UUID: Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(surface.name)
                .font(Typography.subheadline)
                .foregroundStyle(Theme.textPrimary)
            GeometryReader { geo in
                let tallest = spots.compactMap { items[$0.itemID]?.heightCm }.max() ?? 30
                let topBand = geo.size.height - 22
                let scale = min(geo.size.width / max(surface.width, 1), topBand / max(tallest, 1))
                let hostWidth = surface.width * scale
                let originX = (geo.size.width - hostWidth) / 2
                ZStack(alignment: .topLeading) {
                    // The top of the furniture.
                    RoundedRectangle(cornerRadius: 4)
                        .fill(surface.type.planColor.opacity(0.35))
                        .frame(width: hostWidth, height: 18)
                        .offset(x: originX, y: topBand)
                    ForEach(spots) { spot in
                        if let item = items[spot.itemID] {
                            let w = max(item.widthCm * scale, 14)
                            let h = max(item.heightCm * scale, 14)
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Theme.accent.opacity(0.18))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.accent, lineWidth: 1.5))
                                .overlay(Image(systemName: item.type.symbol).font(.system(size: min(w, h) * 0.5)).foregroundStyle(Theme.accent))
                                .frame(width: w, height: h)
                                .offset(x: originX + spot.offsetCm * scale - w / 2, y: topBand - h)
                        }
                    }
                }
            }
            .frame(height: 110)
            .accessibilityHidden(true)
            Text(spots.compactMap { items[$0.itemID]?.name }.formatted(.list(type: .and)))
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
