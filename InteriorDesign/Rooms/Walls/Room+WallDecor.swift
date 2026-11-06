import Foundation

/// Adding, moving, and removing wall decor. Every change keeps the piece
/// fully on its wall.
extension Room {
    func wallLength(_ wall: Int) -> Double {
        PlanGeometry.wallLength(wall, corners: corners)
    }

    func decor(onWall wall: Int) -> [WallDecor] {
        wallDecor.filter { $0.wall == wall }
    }

    func features(onWall wall: Int) -> [FixedFeature] {
        features.filter { $0.wall == wall }
    }

    /// Adds a piece to the emptiest stretch of a wall, at its usual height.
    @discardableResult
    func addDecor(_ kind: DecorKind, wall: Int) -> WallDecor {
        let length = wallLength(wall)
        var piece = WallDecor(kind: kind, wall: wall, centerX: length / 2)
        let taken = features(onWall: wall).map { WallDecorGeometry.rect(for: $0, ceiling: ceilingHeightCm) }
            + decor(onWall: wall).map(\.rect)
        piece.centerX = WallDecorGeometry.freeCenterX(
            width: piece.widthCm, height: piece.centerY, wallLength: length, taken: taken
        )
        piece = WallDecorGeometry.clamped(piece, wallLength: length, ceiling: ceilingHeightCm)
        wallDecor.append(piece)
        updatedAt = Date()
        return piece
    }

    /// Changes one piece, then keeps it on its wall.
    func updateDecor(id: UUID, _ change: (inout WallDecor) -> Void) {
        guard let index = wallDecor.firstIndex(where: { $0.id == id }) else { return }
        var piece = wallDecor[index]
        change(&piece)
        wallDecor[index] = WallDecorGeometry.clamped(piece, wallLength: wallLength(piece.wall), ceiling: ceilingHeightCm)
        updatedAt = Date()
    }

    /// Replaces several pieces at once (for "line them up").
    func replaceDecor(_ pieces: [WallDecor]) {
        for piece in pieces {
            guard let index = wallDecor.firstIndex(where: { $0.id == piece.id }) else { continue }
            wallDecor[index] = WallDecorGeometry.clamped(piece, wallLength: wallLength(piece.wall), ceiling: ceilingHeightCm)
        }
        updatedAt = Date()
    }

    func removeDecor(id: UUID) {
        wallDecor.removeAll { $0.id == id }
        updatedAt = Date()
    }

    func setCeilingHeight(_ cm: Double) {
        ceilingHeightCm = min(max(cm, WallDecorGeometry.ceilingRange.lowerBound), WallDecorGeometry.ceilingRange.upperBound)
        wallDecor = wallDecor.map {
            WallDecorGeometry.clamped($0, wallLength: wallLength($0.wall), ceiling: ceilingHeightCm)
        }
        updatedAt = Date()
    }

    /// Called whenever the outline changes, so pieces follow their walls.
    func moveDecor(from old: [Point2D]) {
        guard !wallDecor.isEmpty else { return }
        wallDecor = WallDecorGeometry.moved(wallDecor, from: old, to: corners, ceiling: ceilingHeightCm)
    }

    /// Furniture from the room's current arrangement that stands against
    /// a wall, as seen from the front.
    func furnitureAgainst(wall: Int) -> [WallFurniture] {
        let boxes = RoomFurniture.placed(layoutItems).map { placed in
            let box = placed.footprint
            return WallDecorGeometry.FloorBox(
                id: placed.item.id, name: placed.item.name,
                minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY,
                height: placed.item.height
            )
        }
        return WallDecorGeometry.furnitureAgainst(wall: wall, corners: corners, boxes: boxes)
    }
}
