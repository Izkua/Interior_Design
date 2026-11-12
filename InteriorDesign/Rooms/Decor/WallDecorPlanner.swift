import Foundation

/// One wall as the wall decor planner sees it. Plain values in cm, so the
/// planner can be tested on its own.
struct PlannerWall: Sendable {
    var index: Int
    var name: String
    var length: Double
    /// Doors and windows, seen from the front. Outlets don't block decor.
    var blocked: [WallRect]
    /// Furniture standing against the wall, seen from the front.
    var furniture: [WallFurniture]
    var furnitureTypes: [UUID: ItemType] = [:]
}

/// A suggested way to hang a room's wall decor.
struct WallDecorSuggestion: Identifiable, Sendable {
    var id: String { label }
    var label: String
    /// One sentence on the idea behind it.
    var detail: String
    var decor: [WallDecor]
    /// Pieces that didn't fit anywhere sensible (they keep their spot).
    var leftOut: [UUID] = []

    var walls: [Int] { Array(Set(decor.map(\.wall))).sorted() }
}

/// Suggests arrangements of wall decor: a group over the main piece of
/// furniture, a gallery wall, and pieces spread around the room. Uses the
/// usual rules of thumb (middle at eye level, a hand's width above
/// furniture, art about two-thirds as wide as the furniture below it)
/// and the pieces' colors, so the boldest piece takes the middle.
enum WallDecorPlanner {
    /// Furniture that makes a good anchor for art, best first.
    static let anchorOrder: [ItemType] = [.sofa, .bed, .dresser, .desk, .tvStand, .table, .shelf]

    static func suggest(
        walls: [PlannerWall],
        pieces: [WallDecor],
        ceiling: Double,
        colors: [UUID: RGB] = [:]
    ) -> [WallDecorSuggestion] {
        guard !walls.isEmpty, !pieces.isEmpty else { return [] }
        var results: [WallDecorSuggestion] = []

        // The main ideas first, then more of each kind: over other pieces
        // of furniture, a gallery on other walls, and spread differently.
        let anchors = allAnchors(walls)
        for (i, anchor) in anchors.enumerated() where i < 4 {
            if let s = aboveAnchor(walls: walls, pieces: pieces, ceiling: ceiling, colors: colors, anchor: anchor) {
                results.append(s)
            }
            if i == 0 {
                if let gallery = galleryWall(walls: walls, pieces: pieces, ceiling: ceiling, colors: colors) {
                    results.append(gallery)
                }
                if pieces.count > 1, let spread = spreadOut(walls: walls, pieces: pieces, ceiling: ceiling, colors: colors) {
                    results.append(spread)
                }
            }
        }
        if anchors.isEmpty {
            if let gallery = galleryWall(walls: walls, pieces: pieces, ceiling: ceiling, colors: colors) { results.append(gallery) }
            if pieces.count > 1, let spread = spreadOut(walls: walls, pieces: pieces, ceiling: ceiling, colors: colors) { results.append(spread) }
        }
        let byFree = walls.sorted { freeWidth($0, ceiling: ceiling, placed: []) > freeWidth($1, ceiling: ceiling, placed: []) }
        for wall in byFree.dropFirst().prefix(2) {
            if let gallery = galleryWall(walls: walls, pieces: pieces, ceiling: ceiling, colors: colors, on: wall) {
                results.append(gallery)
            }
        }
        if pieces.count > 1 {
            for shift in 1..<min(walls.count, 3) {
                if let spread = spreadOut(walls: walls, pieces: pieces, ceiling: ceiling, colors: colors, shift: shift) {
                    results.append(spread)
                }
            }
        }

        // Drop repeats (with one piece, several ideas can come out the same).
        var unique: [WallDecorSuggestion] = []
        for s in results where !unique.contains(where: { same($0.decor, s.decor) || $0.label == s.label }) {
            unique.append(s)
        }
        return unique
    }

    // MARK: Ideas

    /// Art grouped over the main piece of furniture (sofa, bed, ...), the TV
    /// over the TV stand, shelves over the desk, and a mirror on its own.
    static func aboveAnchor(walls: [PlannerWall], pieces: [WallDecor], ceiling: Double, colors: [UUID: RGB],
                            anchor chosen: (wall: PlannerWall, furniture: WallFurniture, type: ItemType)? = nil) -> WallDecorSuggestion? {
        guard let (wall, anchor, anchorType) = chosen ?? bestAnchor(walls) else { return nil }
        var placed: [WallDecor] = []
        var rest = pieces

        // A TV goes over the TV stand when there is one.
        for tv in rest.filter({ $0.kind == .tv }) {
            if let (standWall, stand) = furniture(of: .tvStand, in: walls) {
                var d = tv
                d.wall = standWall.index
                d = WallDecorGeometry.centered(d, above: stand, ceiling: ceiling)
                placed.append(d)
                rest.removeAll { $0.id == tv.id }
            }
        }
        // Wall shelves go over a desk when there is one (and it isn't the anchor).
        if anchorType != .desk, let (deskWall, desk) = furniture(of: .desk, in: walls) {
            let shelves = rest.filter { $0.kind == .shelf }
            if !shelves.isEmpty {
                let row = arranged(shelves, on: deskWall, centerX: desk.rect.midX,
                                   bottom: desk.rect.maxY + 40, ceiling: ceiling, colors: colors, maxWidth: desk.rect.width)
                placed += row
                rest.removeAll { p in shelves.contains { $0.id == p.id } }
            }
        }
        // A mirror looks best on its own, on another wall.
        var mirrors = rest.filter { $0.kind == .mirror }
        if rest.count > mirrors.count {
            rest.removeAll { $0.kind == .mirror }
        } else {
            mirrors = []
        }

        // Everything else in one group over the anchor, about as wide as
        // two-thirds of it.
        let group = rest.filter { $0.kind != .tv }
        if !group.isEmpty {
            // Above anything already hung over the anchor (a TV over its stand).
            let below = placed.filter { $0.wall == wall.index && $0.rect.maxX > anchor.rect.minX && $0.rect.minX < anchor.rect.maxX }
            let bottom = max(anchor.rect.maxY + WallDecorGeometry.gapAboveFurnitureCm,
                             (below.map(\.rect.maxY).max() ?? 0) + WallDecorGeometry.groupGapCm * 2)
            placed += arranged(group, on: wall, centerX: anchor.rect.midX,
                               bottom: bottom,
                               ceiling: ceiling, colors: colors, maxWidth: max(anchor.rect.width * 0.75, 60))
        }
        // TVs with no stand stay where they are.
        let placedIDs = Set(placed.map(\.id))
        placed += rest.filter { $0.kind == .tv && !placedIDs.contains($0.id) }

        let others = walls.filter { $0.index != wall.index }
        for mirror in mirrors {
            let target = others.max { freeWidth($0, ceiling: ceiling, placed: placed) < freeWidth($1, ceiling: ceiling, placed: placed) } ?? wall
            placed.append(alone(mirror, on: target, ceiling: ceiling, placed: placed))
        }

        let name = anchor.name.isEmpty ? anchorType.displayName.lowercased() : anchor.name
        return finish(
            label: "Over the \(name.lowercased())",
            detail: "Groups your art above the \(name.lowercased()), about two-thirds its width, with the boldest piece in the middle.",
            placed: placed, original: pieces, walls: walls, ceiling: ceiling
        )
    }

    /// Every piece of art together on the wall with the most free space,
    /// in a row or a grid centered at eye level.
    static func galleryWall(walls: [PlannerWall], pieces: [WallDecor], ceiling: Double, colors: [UUID: RGB],
                            on chosen: PlannerWall? = nil) -> WallDecorSuggestion? {
        let art = pieces.filter { $0.kind != .tv && $0.kind != .shelf }
        guard art.count >= 2 else { return nil }
        guard let wall = chosen ?? walls.max(by: { freeWidth($0, ceiling: ceiling, placed: []) < freeWidth($1, ceiling: ceiling, placed: []) }) else { return nil }
        let span = freeSpan(wall, height: WallDecorGeometry.eyeLevelCm, ceiling: ceiling, placed: [])
        let group = arranged(art, on: wall, centerX: (span.start + span.end) / 2, middle: WallDecorGeometry.eyeLevelCm,
                             ceiling: ceiling, colors: colors, maxWidth: max(span.end - span.start - 20, 60))
        let placed = group + pieces.filter { p in !art.contains { $0.id == p.id } }
        return finish(
            label: chosen == nil ? "Gallery wall" : "Gallery on the \(wall.name.lowercased())",
            detail: "All your art together on \(wall.name.lowercased()), centered at eye level with even gaps.",
            placed: placed, original: pieces, walls: walls, ceiling: ceiling
        )
    }

    /// The biggest pieces on the biggest walls, one area per wall, each
    /// over furniture when there is some.
    static func spreadOut(walls: [PlannerWall], pieces: [WallDecor], ceiling: Double, colors: [UUID: RGB],
                          shift: Int = 0) -> WallDecorSuggestion? {
        // Boldest and biggest first, so it lands on the best wall.
        let order = pieces.sorted { score($0, colors) > score($1, colors) }
        var wallOrder = walls.sorted { freeWidth($0, ceiling: ceiling, placed: []) > freeWidth($1, ceiling: ceiling, placed: []) }
        // The wall with the main furniture comes first.
        if let anchor = bestAnchor(walls), let i = wallOrder.firstIndex(where: { $0.index == anchor.wall.index }) {
            wallOrder.insert(wallOrder.remove(at: i), at: 0)
        }
        // Other versions start on a different wall.
        if shift > 0, !wallOrder.isEmpty {
            let k = shift % wallOrder.count
            wallOrder = Array(wallOrder[k...] + wallOrder[..<k])
        }
        var placed: [WallDecor] = []
        for (n, piece) in order.enumerated() {
            let wall = wallOrder[n % wallOrder.count]
            var d = piece
            d.wall = wall.index
            let usedFurniture = Set(placed.filter { $0.wall == wall.index }.map(\.centerX))
            if let below = wall.furniture.filter({ !usedFurniture.contains($0.rect.midX) && $0.rect.width >= d.widthCm * 0.8 })
                .max(by: { $0.rect.width < $1.rect.width }), piece.kind != .mirror {
                d = WallDecorGeometry.centered(d, above: below, ceiling: ceiling)
                if overlapsSomething(d, wall: wall, placed: placed, ceiling: ceiling) {
                    d = alone(piece, on: wall, ceiling: ceiling, placed: placed)
                }
            } else {
                d = alone(piece, on: wall, ceiling: ceiling, placed: placed)
            }
            placed.append(d)
        }
        return finish(
            label: shift == 0 ? "Around the room" : "Around the room, version \(shift + 1)",
            detail: "Spreads your pieces over the walls so no wall feels bare, the biggest and boldest on the main wall.",
            placed: placed, original: pieces, walls: walls, ceiling: ceiling
        )
    }

    // MARK: Building blocks

    /// Pieces in a row (or a grid, if a row would be wider than
    /// `maxWidth`), centered on `centerX`. Either the bottom edge sits at
    /// `bottom`, or the middle at `middle`.
    static func arranged(
        _ pieces: [WallDecor], on wall: PlannerWall, centerX: Double, bottom: Double? = nil, middle: Double? = nil,
        ceiling: Double, colors: [UUID: RGB], maxWidth: Double
    ) -> [WallDecor] {
        guard !pieces.isEmpty else { return [] }
        let ordered = centerOut(pieces, colors: colors)
        let gap = WallDecorGeometry.groupGapCm
        let rows = gridRows(ordered, maxWidth: maxWidth, gap: gap)
        let rowHeights = rows.map { $0.map(\.heightCm).max() ?? 0 }
        let totalHeight = rowHeights.reduce(0, +) + gap * Double(rows.count - 1)
        var top: Double
        if let bottom { top = bottom + totalHeight } else { top = (middle ?? WallDecorGeometry.eyeLevelCm) + totalHeight / 2 }
        top = min(top, ceiling - 10)

        var result: [WallDecor] = []
        for (i, row) in rows.enumerated() {
            let rowMiddle = top - rowHeights[i] / 2
            var laid = WallDecorGeometry.row(row.enumerated().map { j, p in var d = p; d.centerX = Double(j); return d },
                                             centerX: centerX, centerY: rowMiddle, gap: gap)
            laid = laid.map { var d = $0; d.wall = wall.index; return d }
            result += laid
            top -= rowHeights[i] + gap
        }
        // Keep the whole group on the wall.
        let left = result.map(\.rect.minX).min() ?? 0
        let right = result.map(\.rect.maxX).max() ?? 0
        let shift = left < 0 ? -left : right > wall.length ? wall.length - right : 0
        return result.map { var d = $0; d.centerX += shift; return WallDecorGeometry.clamped(d, wallLength: wall.length, ceiling: ceiling) }
    }

    /// Splits pieces into rows no wider than `maxWidth`, keeping the order.
    static func gridRows(_ pieces: [WallDecor], maxWidth: Double, gap: Double) -> [[WallDecor]] {
        let total = pieces.reduce(0) { $0 + $1.widthCm } + gap * Double(pieces.count - 1)
        guard total > maxWidth, pieces.count > 1 else { return [pieces] }
        // As few rows as it takes, with the pieces shared out evenly.
        var rowCount = 2
        while rowCount < pieces.count {
            let perRow = Int((Double(pieces.count) / Double(rowCount)).rounded(.up))
            let widest = stride(from: 0, to: pieces.count, by: perRow).map { start in
                let row = pieces[start..<min(start + perRow, pieces.count)]
                return row.reduce(0) { $0 + $1.widthCm } + gap * Double(row.count - 1)
            }.max() ?? 0
            if widest <= maxWidth { break }
            rowCount += 1
        }
        let perRow = Int((Double(pieces.count) / Double(rowCount)).rounded(.up))
        return stride(from: 0, to: pieces.count, by: perRow).map { Array(pieces[$0..<min($0 + perRow, pieces.count)]) }
    }

    /// The boldest, biggest piece in the middle, the others alternating
    /// out to the sides, so the group looks balanced.
    static func centerOut(_ pieces: [WallDecor], colors: [UUID: RGB]) -> [WallDecor] {
        let ranked = pieces.sorted { score($0, colors) > score($1, colors) }
        var result: [WallDecor] = []
        for (i, piece) in ranked.enumerated() {
            if i % 2 == 0 { result.append(piece) } else { result.insert(piece, at: 0) }
        }
        return result
    }

    /// Size, plus a bonus for strong color.
    static func score(_ piece: WallDecor, _ colors: [UUID: RGB]) -> Double {
        let color = piece.itemID.flatMap { colors[$0] } ?? colors[piece.id]
        return piece.widthCm * piece.heightCm * (1 + (color?.saturation ?? 0))
    }

    /// One piece on its own, at eye level, in the widest free stretch.
    static func alone(_ piece: WallDecor, on wall: PlannerWall, ceiling: Double, placed: [WallDecor]) -> WallDecor {
        var d = piece
        d.wall = wall.index
        d.centerY = piece.kind.defaultCenterHeight
        let taken = takenRects(wall, ceiling: ceiling, placed: placed)
        d.centerX = WallDecorGeometry.freeCenterX(width: d.widthCm, height: d.centerY, wallLength: wall.length, taken: taken)
        return WallDecorGeometry.clamped(d, wallLength: wall.length, ceiling: ceiling)
    }

    /// Every piece of furniture against a wall, best anchor first.
    static func allAnchors(_ walls: [PlannerWall]) -> [(wall: PlannerWall, furniture: WallFurniture, type: ItemType)] {
        let all = walls.flatMap { w in w.furniture.map { (wall: w, furniture: $0, type: w.furnitureTypes[$0.id] ?? .other) } }
        return all
            .filter { $0.furniture.rect.width >= 40 }
            .sorted { a, b in
                let ra = anchorOrder.firstIndex(of: a.type) ?? 99, rb = anchorOrder.firstIndex(of: b.type) ?? 99
                return ra != rb ? ra < rb : a.furniture.rect.width > b.furniture.rect.width
            }
    }

    static func bestAnchor(_ walls: [PlannerWall]) -> (wall: PlannerWall, furniture: WallFurniture, type: ItemType)? {
        for type in anchorOrder {
            if let (wall, f) = furniture(of: type, in: walls) { return (wall, f, type) }
        }
        // Anything else against a wall, widest first.
        let all = walls.flatMap { w in w.furniture.map { (w, $0) } }
        guard let (wall, f) = all.max(by: { $0.1.rect.width < $1.1.rect.width }) else { return nil }
        return (wall, f, wall.furnitureTypes[f.id] ?? .other)
    }

    static func furniture(of type: ItemType, in walls: [PlannerWall]) -> (PlannerWall, WallFurniture)? {
        let matches = walls.flatMap { w in w.furniture.filter { w.furnitureTypes[$0.id] == type }.map { (w, $0) } }
        return matches.max { $0.1.rect.width < $1.1.rect.width }
    }

    static func takenRects(_ wall: PlannerWall, ceiling: Double, placed: [WallDecor]) -> [WallRect] {
        wall.blocked + placed.filter { $0.wall == wall.index }.map(\.rect)
    }

    /// The widest free stretch at a height, as (start, end).
    static func freeSpan(_ wall: PlannerWall, height: Double, ceiling: Double, placed: [WallDecor]) -> (start: Double, end: Double) {
        let spans = takenRects(wall, ceiling: ceiling, placed: placed)
            .filter { $0.minY <= height && $0.maxY >= height }
            .map { (max($0.minX, 0), min($0.maxX, wall.length)) }
            .sorted { $0.0 < $1.0 }
        var best = (start: 0.0, end: 0.0)
        var cursor = 0.0
        for (s, e) in spans {
            if s - cursor > best.end - best.start { best = (cursor, s) }
            cursor = max(cursor, e)
        }
        if wall.length - cursor > best.end - best.start { best = (cursor, wall.length) }
        return best
    }

    static func freeWidth(_ wall: PlannerWall, ceiling: Double, placed: [WallDecor]) -> Double {
        let span = freeSpan(wall, height: WallDecorGeometry.eyeLevelCm, ceiling: ceiling, placed: placed)
        return span.end - span.start
    }

    static func overlapsSomething(_ d: WallDecor, wall: PlannerWall, placed: [WallDecor], ceiling: Double) -> Bool {
        takenRects(wall, ceiling: ceiling, placed: placed).contains { d.rect.overlaps($0) }
    }

    /// Fixes pieces that ended up over a window or door, and puts back
    /// any piece that was left out.
    static func finish(label: String, detail: String, placed: [WallDecor], original: [WallDecor], walls: [PlannerWall], ceiling: Double) -> WallDecorSuggestion? {
        var result: [WallDecor] = []
        let byIndex = Dictionary(uniqueKeysWithValues: walls.map { ($0.index, $0) })
        for piece in placed {
            guard let wall = byIndex[piece.wall] else { result.append(piece); continue }
            if wall.blocked.contains(where: { piece.rect.overlaps($0) }) {
                result.append(alone(piece, on: wall, ceiling: ceiling, placed: result))
            } else {
                result.append(piece)
            }
        }
        let leftOut = original.filter { p in !result.contains { $0.id == p.id } }
        result += leftOut
        return WallDecorSuggestion(label: label, detail: detail, decor: result, leftOut: leftOut.map(\.id))
    }

    /// True when two arrangements put every piece in the same spot.
    static func same(_ a: [WallDecor], _ b: [WallDecor]) -> Bool {
        guard a.count == b.count else { return false }
        let other = Dictionary(uniqueKeysWithValues: b.map { ($0.id, $0) })
        return a.allSatisfy { p in
            guard let q = other[p.id] else { return false }
            return p.wall == q.wall && abs(p.centerX - q.centerX) < 2 && abs(p.centerY - q.centerY) < 2
        }
    }
}
