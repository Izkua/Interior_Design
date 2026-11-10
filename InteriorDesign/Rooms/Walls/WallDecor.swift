import Foundation

/// The kinds of things that hang on a wall.
enum DecorKind: String, Codable, CaseIterable, Identifiable {
    case frame
    case poster
    case canvas
    case mirror
    case shelf
    case clock
    case tv
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frame: return "Frame"
        case .poster: return "Poster"
        case .canvas: return "Canvas"
        case .mirror: return "Mirror"
        case .shelf: return "Shelf"
        case .clock: return "Clock"
        case .tv: return "TV"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .frame: return "photo"
        case .poster: return "doc.richtext"
        case .canvas: return "paintpalette"
        case .mirror: return "oval.portrait"
        case .shelf: return "books.vertical"
        case .clock: return "clock"
        case .tv: return "tv"
        case .other: return "square.dashed"
        }
    }

    /// A typical size to start from, in centimeters: width, height, depth.
    var defaultSize: (width: Double, height: Double, depth: Double) {
        switch self {
        case .frame: return (40, 50, 3)
        case .poster: return (50, 70, 1)
        case .canvas: return (80, 60, 4)
        case .mirror: return (60, 90, 3)
        case .shelf: return (80, 4, 20)
        case .clock: return (35, 35, 5)
        case .tv: return (123, 71, 6)
        case .other: return (40, 40, 5)
        }
    }

    /// Where the middle usually goes, in cm above the floor. Art sits at eye
    /// level; a TV sits lower so it's comfortable from a sofa.
    var defaultCenterHeight: Double {
        switch self {
        case .tv: return 110
        case .clock: return 170
        default: return WallDecorGeometry.eyeLevelCm
        }
    }

    /// Shelves stick out from the wall, so their depth matters.
    var showsDepth: Bool { self == .shelf || self == .tv }
}

/// One thing hanging on a wall, seen from the front.
struct WallDecor: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: DecorKind
    var name: String
    /// Index of the wall (wall `i` runs from corner `i` to corner `i + 1`).
    var wall: Int
    /// Distance from the wall's left end (its first corner, when you stand
    /// in the room facing it) to the middle of the piece, in cm.
    var centerX: Double
    /// Height of the middle of the piece above the floor, in cm.
    var centerY: Double
    var widthCm: Double
    var heightCm: Double
    /// How far it sticks out from the wall. Matters for shelves.
    var depthCm: Double
    /// The piece in Current Items, if it's one the person owns.
    var itemID: UUID?

    init(kind: DecorKind, name: String? = nil, wall: Int, centerX: Double, centerY: Double? = nil,
         widthCm: Double? = nil, heightCm: Double? = nil, depthCm: Double? = nil, itemID: UUID? = nil) {
        let size = kind.defaultSize
        self.kind = kind
        self.name = name ?? kind.title
        self.wall = wall
        self.centerX = centerX
        self.centerY = centerY ?? kind.defaultCenterHeight
        self.widthCm = widthCm ?? size.width
        self.heightCm = heightCm ?? size.height
        self.depthCm = depthCm ?? size.depth
        self.itemID = itemID
    }

    // Decoded by hand so fields added later fall back to defaults instead
    // of failing to load rooms saved by an older build.
    private enum CodingKeys: String, CodingKey {
        case id, kind, name, wall, centerX, centerY, widthCm, heightCm, depthCm, itemID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(DecorKind.self, forKey: .kind) ?? .other
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? kind.title
        wall = try c.decodeIfPresent(Int.self, forKey: .wall) ?? 0
        centerX = try c.decodeIfPresent(Double.self, forKey: .centerX) ?? 0
        centerY = try c.decodeIfPresent(Double.self, forKey: .centerY) ?? kind.defaultCenterHeight
        widthCm = try c.decodeIfPresent(Double.self, forKey: .widthCm) ?? kind.defaultSize.width
        heightCm = try c.decodeIfPresent(Double.self, forKey: .heightCm) ?? kind.defaultSize.height
        depthCm = try c.decodeIfPresent(Double.self, forKey: .depthCm) ?? kind.defaultSize.depth
        itemID = try c.decodeIfPresent(UUID.self, forKey: .itemID)
    }

    var rect: WallRect {
        WallRect(minX: centerX - widthCm / 2, minY: centerY - heightCm / 2,
                 maxX: centerX + widthCm / 2, maxY: centerY + heightCm / 2)
    }
}

/// A rectangle on the front view of a wall, in cm. x runs left to right
/// along the wall; y runs up from the floor.
struct WallRect: Equatable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var midX: Double { (minX + maxX) / 2 }
    var midY: Double { (minY + maxY) / 2 }

    /// True when the two overlap by more than a hair (touching edges don't count).
    func overlaps(_ other: WallRect, margin: Double = 0.5) -> Bool {
        minX < other.maxX - margin && other.minX < maxX - margin
            && minY < other.maxY - margin && other.minY < maxY - margin
    }
}

/// A piece of furniture standing against a wall, as seen from the front.
struct WallFurniture: Equatable, Identifiable {
    var id: UUID
    var name: String
    /// Where it sits along the wall and how tall it is (minY is the floor).
    var rect: WallRect
}

/// A line to draw while dragging, showing what the piece lined up with.
struct DecorGuide: Equatable {
    enum Axis: Equatable { case vertical, horizontal }
    var axis: Axis
    /// x for a vertical line, y for a horizontal one, in cm.
    var position: Double
}

/// Math for the wall front view. Everything is in centimeters and has no
/// UI, so it can be tested on its own.
enum WallDecorGeometry {
    /// Gallery rule of thumb: the middle of a picture about 145 cm (57″)
    /// above the floor.
    static let eyeLevelCm = 145.0
    /// 8 feet, a common ceiling. The person can change it per room.
    static let defaultCeilingCm = 244.0
    static let ceilingRange: ClosedRange<Double> = 180...600
    /// Leave about this much between a piece and the furniture below it.
    static let gapAboveFurnitureCm = 20.0
    /// Space between pieces in a group.
    static let groupGapCm = 8.0
    /// How close (in cm) a piece must get to a line before it snaps to it.
    static let snapCm = 4.0

    // MARK: Doors, windows, outlets

    static let doorHeightCm = 203.0
    static let windowSillCm = 90.0
    static let windowTopCm = 210.0
    static let outletCenterCm = 30.0
    static let outletHeightCm = 12.0

    /// Where a door, window, or outlet sits on the wall's front view.
    /// The room plan only knows widths, so heights are typical values.
    static func rect(for feature: FixedFeature, ceiling: Double) -> WallRect {
        let minX = feature.offsetCm - feature.widthCm / 2
        let maxX = feature.offsetCm + feature.widthCm / 2
        switch feature.kind {
        case .door:
            return WallRect(minX: minX, minY: 0, maxX: maxX, maxY: min(doorHeightCm, ceiling))
        case .window:
            let top = min(windowTopCm, ceiling - 5)
            return WallRect(minX: minX, minY: min(windowSillCm, top - 10), maxX: maxX, maxY: top)
        case .outlet:
            return WallRect(minX: minX, minY: outletCenterCm - outletHeightCm / 2,
                            maxX: maxX, maxY: outletCenterCm + outletHeightCm / 2)
        }
    }

    // MARK: Keeping things on the wall

    /// The piece moved (and shrunk if it must be) so it fits fully on a
    /// wall of the given length, between the floor and the ceiling.
    static func clamped(_ decor: WallDecor, wallLength: Double, ceiling: Double) -> WallDecor {
        var d = decor
        d.widthCm = min(max(d.widthCm, 1), max(wallLength, 1))
        d.heightCm = min(max(d.heightCm, 1), max(ceiling, 1))
        d.centerX = clamp(d.centerX, d.widthCm / 2, wallLength - d.widthCm / 2)
        d.centerY = clamp(d.centerY, d.heightCm / 2, ceiling - d.heightCm / 2)
        return d
    }

    /// Pieces after the room outline changed from `old` to `new` corners.
    /// With the same number of corners each piece stays on its wall, the
    /// same fraction of the way along. When corners were added or removed,
    /// each moves to whichever new wall passes closest to where it was.
    static func moved(_ decor: [WallDecor], from old: [Point2D], to new: [Point2D], ceiling: Double) -> [WallDecor] {
        guard new.count >= 2 else { return decor }
        return decor.map { piece in
            var d = piece
            if old.count == new.count {
                d.wall = min(max(d.wall, 0), new.count - 1)
                let oldLength = PlanGeometry.wallLength(d.wall, corners: old)
                let newLength = PlanGeometry.wallLength(d.wall, corners: new)
                if oldLength > 0 { d.centerX = d.centerX / oldLength * newLength }
            } else if old.count >= 2 {
                let spot = PlanGeometry.point(onWall: d.wall, offset: d.centerX, corners: old)
                let target = PlanGeometry.nearestWall(to: spot, corners: new)
                d.wall = target.wall
                d.centerX = target.offset
            }
            return clamped(d, wallLength: PlanGeometry.wallLength(d.wall, corners: new), ceiling: ceiling)
        }
    }

    /// The middle of the widest open stretch of the wall for a new piece
    /// of the given width. Doors, windows, and other pieces that cross
    /// `height` count as taken.
    static func freeCenterX(width: Double, height: Double, wallLength: Double, taken: [WallRect]) -> Double {
        guard wallLength > 0 else { return 0 }
        let spans = taken
            .filter { $0.minY <= height && $0.maxY >= height }
            .map { (start: max($0.minX, 0), end: min($0.maxX, wallLength)) }
            .sorted { $0.start < $1.start }
        var best = (start: 0.0, end: 0.0)
        var cursor = 0.0
        for span in spans {
            if span.start - cursor > best.end - best.start { best = (cursor, span.start) }
            cursor = max(cursor, span.end)
        }
        if wallLength - cursor > best.end - best.start { best = (cursor, wallLength) }
        let middle = (best.start + best.end) / 2
        return clamp(middle, width / 2, wallLength - width / 2)
    }

    // MARK: Snapping while dragging

    /// The piece nudged onto a nearby line, plus the lines it snapped to.
    /// It snaps to the middle of the wall, eye level, the middle of the
    /// furniture below, and the edges and middles of the other pieces.
    static func snapped(
        _ decor: WallDecor,
        wallLength: Double,
        others: [WallDecor],
        furniture: [WallFurniture] = [],
        distance: Double = snapCm
    ) -> (decor: WallDecor, guides: [DecorGuide]) {
        var d = decor
        var guides: [DecorGuide] = []
        let r = decor.rect

        // Each candidate is a line, and which part of the piece lines up
        // with it: its left edge, middle, or right edge (or bottom/top).
        var xLines: [(line: Double, edge: Double)] = [(wallLength / 2, 0)]
        var yLines: [(line: Double, edge: Double)] = [(eyeLevelCm, 0)]
        for f in furniture {
            xLines.append((f.rect.midX, 0))
        }
        for o in others where o.id != decor.id {
            let or = o.rect
            xLines += [(or.minX, -r.width / 2), (or.midX, 0), (or.maxX, r.width / 2)]
            yLines += [(or.minY, -r.height / 2), (or.midY, 0), (or.maxY, r.height / 2)]
        }

        if let best = xLines.min(by: { abs(r.midX + $0.edge - $0.line) < abs(r.midX + $1.edge - $1.line) }),
           abs(r.midX + best.edge - best.line) <= distance {
            d.centerX = best.line - best.edge
            guides.append(DecorGuide(axis: .vertical, position: best.line))
        }
        if let best = yLines.min(by: { abs(r.midY + $0.edge - $0.line) < abs(r.midY + $1.edge - $1.line) }),
           abs(r.midY + best.edge - best.line) <= distance {
            d.centerY = best.line - best.edge
            guides.append(DecorGuide(axis: .horizontal, position: best.line))
        }
        return (d, guides)
    }

    // MARK: Furniture against the wall

    /// A piece of furniture's floor box, for working out what stands
    /// against a wall.
    struct FloorBox {
        var id: UUID
        var name: String
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double
        var height: Double
    }

    /// Furniture standing within `reach` cm of the wall, as seen from the
    /// front. Corners are clockwise on screen, so the room is to the
    /// right of each wall's direction.
    static func furnitureAgainst(
        wall: Int,
        corners: [Point2D],
        boxes: [FloorBox],
        reach: Double = 40
    ) -> [WallFurniture] {
        let count = corners.count
        guard count >= 3 else { return [] }
        let i = ((wall % count) + count) % count
        let a = corners[i]
        let b = corners[(i + 1) % count]
        let length = PlanGeometry.distance(a, b)
        guard length > 0 else { return [] }
        let dir = Point2D(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
        let inward = Point2D(x: -dir.y, y: dir.x)

        return boxes.compactMap { box in
            let points = [
                Point2D(x: box.minX, y: box.minY), Point2D(x: box.maxX, y: box.minY),
                Point2D(x: box.maxX, y: box.maxY), Point2D(x: box.minX, y: box.maxY)
            ]
            let along = points.map { ($0.x - a.x) * dir.x + ($0.y - a.y) * dir.y }
            let away = points.map { ($0.x - a.x) * inward.x + ($0.y - a.y) * inward.y }
            guard let nearest = away.min(), nearest > -reach, nearest <= reach,
                  let start = along.min(), let end = along.max(),
                  end > 0, start < length else { return nil }
            return WallFurniture(
                id: box.id,
                name: box.name,
                rect: WallRect(minX: max(start, 0), minY: 0, maxX: min(end, length), maxY: box.height)
            )
        }
    }

    /// The piece centered above a piece of furniture, with its bottom edge
    /// a little above the furniture's top.
    static func centered(_ decor: WallDecor, above furniture: WallFurniture, ceiling: Double) -> WallDecor {
        var d = decor
        d.centerX = furniture.rect.midX
        d.centerY = max(furniture.rect.maxY + gapAboveFurnitureCm + d.heightCm / 2, d.centerY)
        // If that would hit the ceiling, sit as high as fits.
        d.centerY = min(d.centerY, ceiling - d.heightCm / 2)
        return d
    }

    // MARK: Groups

    /// Pieces hung side by side, in their current left-to-right order, with
    /// an even gap, the whole row centered on (`centerX`, `centerY`).
    static func row(_ decor: [WallDecor], centerX: Double, centerY: Double, gap: Double = groupGapCm) -> [WallDecor] {
        guard !decor.isEmpty else { return [] }
        let ordered = decor.sorted { $0.centerX < $1.centerX }
        let total = ordered.reduce(0) { $0 + $1.widthCm } + gap * Double(ordered.count - 1)
        var x = centerX - total / 2
        return ordered.map { piece in
            var d = piece
            d.centerX = x + d.widthCm / 2
            d.centerY = centerY
            x += d.widthCm + gap
            return d
        }
    }

    // MARK: Problems

    /// Short warnings for a piece where it hangs now. Shown, never blocked.
    static func problems(
        for decor: WallDecor,
        features: [FixedFeature],
        others: [WallDecor],
        ceiling: Double
    ) -> [String] {
        let r = decor.rect
        var result: [String] = []
        for f in features where f.kind != .outlet && r.overlaps(rect(for: f, ceiling: ceiling)) {
            result.append("Covers the \(f.kind.title.lowercased())")
        }
        for o in others where o.id != decor.id && r.overlaps(o.rect) {
            result.append("Overlaps \(o.name)")
        }
        // Deep shelves at head height are easy to walk into.
        if decor.kind == .shelf, decor.depthCm > 25, r.minY > 120, r.minY < 185 {
            result.append("Deep shelf at head height")
        }
        return Array(Set(result)).sorted()
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        guard low <= high else { return (low + high) / 2 }
        return min(max(value, low), high)
    }
}
