import Foundation

/// What the decor fit checks need to know about a room. Plain values, so
/// they can be checked off the main thread.
struct DecorSpace: Sendable {
    var ceiling: Double = WallDecorGeometry.defaultCeilingCm
    var features: [FixedFeature] = []
    var wallDecor: [WallDecor] = []
    var surfaces: [DecorSurface] = []
    /// How much of each surface's width small decor already takes, in cm.
    var usedWidth: [UUID: Double] = [:]

    func walls(placed: [PlacedItem], corners: [Point2D]) -> [PlannerWall] {
        let boxes = placed.map { p in
            let box = p.footprint
            return WallDecorGeometry.FloorBox(id: p.item.id, name: p.item.name, minX: box.minX, minY: box.minY,
                                              maxX: box.maxX, maxY: box.maxY, height: p.item.height)
        }
        return corners.indices.map { wall in
            PlannerWall(
                index: wall,
                name: PlanGeometry.wallName(wall, cornerCount: corners.count),
                length: PlanGeometry.wallLength(wall, corners: corners),
                blocked: features.filter { $0.wall == wall && $0.kind != .outlet }.map { WallDecorGeometry.rect(for: $0, ceiling: ceiling) },
                furniture: WallDecorGeometry.furnitureAgainst(wall: wall, corners: corners, boxes: boxes)
            )
        }
    }
}

/// Checks wall decor against free wall space and small decor against free
/// space on furniture tops. Products without a size are never marked as fitting.
enum DecorFit {
    static func wall(_ product: CatalogProduct, walls: [PlannerWall], space: DecorSpace) -> FitResult {
        guard let width = product.widthCm, width > 0, let height = product.heightCm, height > 0 else { return .unknownSize }
        return wall(width: width, height: height, walls: walls, space: space)
    }

    static func wall(width: Double, height: Double, walls: [PlannerWall], space: DecorSpace) -> FitResult {
        guard !walls.isEmpty else { return .doesNotFit(reason: "Draw the room's walls first.") }
        guard height <= space.ceiling - 20 else { return .doesNotFit(reason: "It's taller than your walls.") }
        let best = walls
            .map { ($0, WallDecorPlanner.freeSpan($0, height: WallDecorGeometry.eyeLevelCm, ceiling: space.ceiling, placed: space.wallDecor)) }
            .max { ($0.1.end - $0.1.start) < ($1.1.end - $1.1.start) }
        if let (wall, span) = best, span.end - span.start >= width + 10 {
            return .fitsSpace("Fits on \(wall.name.hasPrefix("Wall") ? wall.name : wall.name.lowercased())")
        }
        return .doesNotFit(reason: "No wall has a free stretch that wide at eye level, between the doors, windows, and what's already hung.")
    }

    static func surface(_ product: CatalogProduct, space: DecorSpace) -> FitResult {
        guard let type = product.type, let width = product.widthCm, width > 0,
              let depth = product.depthCm, depth > 0, let height = product.heightCm, height > 0 else { return .unknownSize }
        return surface(type: type, width: width, depth: depth, height: height, space: space)
    }

    static func surface(type: ItemType, width: Double, depth: Double, height: Double, space: DecorSpace) -> FitResult {
        if type == .plant, height >= SmallDecorPlanner.floorPlantHeight { return .fitsSpace("Stands on the floor") }
        guard !space.surfaces.isEmpty else {
            return .doesNotFit(reason: "There's nothing to put it on yet. Add a desk, table, dresser, shelf, or TV stand to the room.")
        }
        let wanted = SmallDecorPlanner.hosts(for: type)
        let fitting = space.surfaces.filter { s in
            guard let host = SmallDecorPlanner.host(s), wanted.contains(host), depth <= s.depth + 2 else { return false }
            let used = space.usedWidth[s.id] ?? 0
            let gap = used > 0 ? DecorSurface.gap : 0
            return used + gap + width <= s.width - 2 * DecorSurface.margin
        }
        .sorted { (wanted.firstIndex(of: SmallDecorPlanner.host($0)!) ?? 99) < (wanted.firstIndex(of: SmallDecorPlanner.host($1)!) ?? 99) }
        if let first = fitting.first {
            return .fitsSpace("Fits on the \(first.name.lowercased())")
        }
        return .doesNotFit(reason: "None of your surfaces that suit it has a free space that big.")
    }
}

extension Room {
    /// The room's decor, as the fit checks need it.
    @MainActor
    var decorSpace: DecorSpace {
        let widths = Dictionary(items(in: .smallDecor).map { ($0.uuid, $0.widthCm) }, uniquingKeysWith: { a, _ in a })
        var used: [UUID: Double] = [:]
        for spot in surfaceDecor {
            guard let host = spot.hostID, let w = widths[spot.itemID] else { continue }
            used[host, default: -DecorSurface.gap] += w + DecorSurface.gap
        }
        return DecorSpace(ceiling: ceilingHeightCm, features: features, wallDecor: wallDecor,
                          surfaces: decorSurfaces, usedWidth: used)
    }
}
