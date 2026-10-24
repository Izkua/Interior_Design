import Foundation

/// A rule a layout breaks. A layout with any of these is never suggested,
/// and a hand-adjusted layout shows them as warnings.
enum LayoutProblem: Equatable, Sendable {
    case outsideRoom(UUID)
    case overlaps(UUID, UUID)
    /// The first item sits in the space the second needs in front of it.
    case inFrontOf(UUID, UUID)
    case blocksDoor(UUID)
    case blocksWindow(UUID)
    /// No walking path from the door reaches the item.
    case unreachable(UUID)

    /// The items the problem is about, to highlight them.
    var itemIDs: [UUID] {
        switch self {
        case .outsideRoom(let a), .blocksDoor(let a), .blocksWindow(let a), .unreachable(let a):
            return [a]
        case .overlaps(let a, let b), .inFrontOf(let a, let b):
            return [a, b]
        }
    }

    /// A sentence for the person, using item names.
    func message(names: [UUID: String]) -> String {
        func name(_ id: UUID) -> String { names[id] ?? "An item" }
        switch self {
        case .outsideRoom(let a): return "\(name(a)) doesn't fit inside the room there."
        case .overlaps(let a, let b): return "\(name(a)) overlaps \(name(b))."
        case .inFrontOf(let a, let b): return "\(name(a)) is in the space \(name(b)) needs in front of it."
        case .blocksDoor(let a): return "\(name(a)) blocks a door from opening."
        case .blocksWindow(let a): return "\(name(a)) is tall and blocks a window."
        case .unreachable(let a): return "There's no clear path from the door to \(name(a))."
        }
    }
}

/// Checks the hard rules for one room. Build it once per room, then check
/// many arrangements; the room's outline and doors are worked out up front.
struct LayoutRules {
    let room: LayoutRoom
    let grid: FloorGrid
    /// Space each door needs to swing open (or to step through).
    let doorZones: [Box]
    /// Space in front of each window that tall furniture must leave clear.
    let windowZones: [Box]
    /// Outlets, as points on the walls.
    let outlets: [Point2D]
    /// Window centers, for desks that want light and seating that faces a view.
    let windowCenters: [Point2D]
    /// The balance point of the floor.
    let middle: Point2D

    /// Half the width of a walking path: 38 cm makes a 76 cm (30 in) path,
    /// the narrow end of the usual 76–91 cm guidance.
    static let pathHalfWidth = 38.0

    init(room: LayoutRoom) {
        self.room = room
        grid = FloorGrid(corners: room.corners)
        var doors: [Box] = []
        var windows: [Box] = []
        for feature in room.features {
            switch feature.kind {
            case .door:
                // An inward door sweeps a square as deep as it is wide;
                // either way people need room to step in.
                let depth = feature.opensInward ? feature.widthCm : 60
                doors.append(Self.zone(feature, depth: depth, corners: room.corners))
            case .window:
                windows.append(Self.zone(feature, depth: 40, corners: room.corners))
            case .outlet:
                break
            }
        }
        doorZones = doors
        windowZones = windows

        // Worked out once here, because the engine asks thousands of times.
        func points(_ kind: FeatureKind) -> [Point2D] {
            room.features.filter { $0.kind == kind }.map {
                PlanGeometry.point(onWall: $0.wall, offset: $0.offsetCm, corners: room.corners)
            }
        }
        outlets = points(.outlet)
        windowCenters = points(.window)
        middle = PolygonGeometry.centroid(room.corners)
    }

    // MARK: Checking one item against what is already placed

    /// The problems a new item would cause, not counting the walking path
    /// (which is slower to check, so the engine checks it last).
    func quickProblems(_ new: PlacedItem, among placed: [PlacedItem]) -> [LayoutProblem] {
        var problems: [LayoutProblem] = []
        let id = new.item.id
        let box = new.footprint

        if !grid.containsBox(box) {
            problems.append(.outsideRoom(id))
        }
        if let clearance = new.clearance, !grid.containsBox(clearance) {
            // Facing a wall, or too close to one to use.
            problems.append(.outsideRoom(id))
        }
        if !new.item.liesFlat {
            if doorZones.contains(where: { $0.overlaps(box) }) {
                problems.append(.blocksDoor(id))
            }
            if new.item.isTall, windowZones.contains(where: { $0.overlaps(box) }) {
                problems.append(.blocksWindow(id))
            }
        }

        for other in placed where !other.item.liesFlat && !new.item.liesFlat {
            if box.overlaps(other.footprint) {
                problems.append(.overlaps(id, other.item.id))
                continue
            }
            if let space = other.clearance, box.overlaps(space), !Self.mayStandIn(new.item, frontOf: other.item) {
                problems.append(.inFrontOf(id, other.item.id))
            }
            if let space = new.clearance, space.overlaps(other.footprint), !Self.mayStandIn(other.item, frontOf: new.item) {
                problems.append(.inFrontOf(other.item.id, id))
            }
        }
        return problems
    }

    /// A chair may stand in front of a desk or table: that is where it goes.
    static func mayStandIn(_ item: LayoutItem, frontOf other: LayoutItem) -> Bool {
        item.type == .chair && (other.type == .desk || other.type == .table)
    }

    /// Every rule, for a whole arrangement. Used for hand-adjusted layouts.
    func problems(in placed: [PlacedItem]) -> [LayoutProblem] {
        var problems: [LayoutProblem] = []
        for (index, item) in placed.enumerated() {
            // Pairs are checked once: each item against the ones before it.
            for problem in quickProblems(item, among: Array(placed[..<index])) where !problems.contains(problem) {
                problems.append(problem)
            }
        }
        for id in unreachableItems(in: placed) {
            problems.append(.unreachable(id))
        }
        return problems
    }

    // MARK: Walking path

    /// Items that need to be reached but have no walking path to them from
    /// a door.
    func unreachableItems(in placed: [PlacedItem]) -> [UUID] {
        let walk = grid.walkableCells(blockedBy: placed.filter { !$0.item.liesFlat }.map(\.footprint), halfWidth: Self.pathHalfWidth)
        let starts = doorZones.isEmpty
            ? Array(walk.indices.filter { walk[$0] }.prefix(1))
            : doorZones.flatMap { grid.cells(in: $0) }.filter { walk[$0] }
        if starts.isEmpty {
            // No room to walk in at all.
            return placed.filter { needsAccess($0.item) }.map(\.item.id)
        }
        let reached = grid.flood(from: starts, through: walk)

        return placed.filter { needsAccess($0.item) }.compactMap { item in
            let target = (item.clearance ?? item.footprint).expanded(by: Self.pathHalfWidth + 8)
            let ok = grid.cells(in: target).contains { reached[$0] }
            return ok ? nil : item.item.id
        }
    }

    /// Share of the open floor a person can walk to, 0 to 1.
    func walkableShare(of placed: [PlacedItem]) -> Double {
        let walk = grid.walkableCells(blockedBy: placed.filter { !$0.item.liesFlat }.map(\.footprint), halfWidth: Self.pathHalfWidth)
        let open = grid.inside.filter { $0 }.count
        guard open > 0 else { return 0 }
        return Double(walk.filter { $0 }.count) / Double(open)
    }

    private func needsAccess(_ item: LayoutItem) -> Bool {
        switch item.type {
        case .lamp, .rug, .tvStand: return false
        case .table: return !item.isCoffeeTable
        default: return true
        }
    }

    // MARK: Helpers

    /// The upright box covering a strip `depth` cm into the room in front
    /// of a door or window.
    private static func zone(_ feature: FixedFeature, depth: Double, corners: [Point2D]) -> Box {
        let count = corners.count
        let wall = PolygonGeometry.wrap(feature.wall, count)
        let a = corners[wall]
        let b = corners[(wall + 1) % count]
        let length = max(PlanGeometry.distance(a, b), 0.001)
        // Into the room, for corners listed clockwise on screen.
        let inward = Point2D(x: -(b.y - a.y) / length, y: (b.x - a.x) / length)
        let start = PlanGeometry.point(onWall: wall, offset: feature.offsetCm - feature.widthCm / 2, corners: corners)
        let end = PlanGeometry.point(onWall: wall, offset: feature.offsetCm + feature.widthCm / 2, corners: corners)
        let points = [start, end,
                      Point2D(x: start.x + inward.x * depth, y: start.y + inward.y * depth),
                      Point2D(x: end.x + inward.x * depth, y: end.y + inward.y * depth)]
        return Box(
            minX: points.map(\.x).min()!, minY: points.map(\.y).min()!,
            maxX: points.map(\.x).max()!, maxY: points.map(\.y).max()!
        )
    }
}

// MARK: - Floor grid

/// The room's floor cut into small squares, for the walking-path check.
/// Squares are 10 cm in normal rooms and grow in very big ones, so the
/// check never has more than about 8,000 squares to look at.
struct FloorGrid: Sendable {
    /// Side of one square, in cm.
    let cell: Double

    let originX: Double
    let originY: Double
    let columns: Int
    let rows: Int
    /// True for squares whose center is inside the room.
    let inside: [Bool]
    let corners: [Point2D]

    init(corners: [Point2D]) {
        self.corners = corners
        originX = corners.map(\.x).min() ?? 0
        originY = corners.map(\.y).min() ?? 0
        let width = (corners.map(\.x).max() ?? 0) - originX
        let height = (corners.map(\.y).max() ?? 0) - originY
        let cell = max(10, (width * height / 8_000).squareRoot().rounded(.up))
        self.cell = cell
        columns = max(Int((width / cell).rounded(.up)), 1)
        rows = max(Int((height / cell).rounded(.up)), 1)

        var mask = [Bool](repeating: false, count: columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let center = Point2D(x: originX + (Double(column) + 0.5) * cell, y: originY + (Double(row) + 0.5) * cell)
                mask[row * columns + column] = Self.polygonContains(center, corners: corners)
            }
        }
        inside = mask
    }

    func center(of index: Int) -> Point2D {
        Point2D(
            x: originX + (Double(index % columns) + 0.5) * cell,
            y: originY + (Double(index / columns) + 0.5) * cell
        )
    }

    /// Indexes of the squares whose centers fall in a box.
    func cells(in box: Box) -> [Int] {
        let c0 = max(Int(((box.minX - originX) / cell).rounded(.down)), 0)
        let c1 = min(Int(((box.maxX - originX) / cell).rounded(.up)), columns - 1)
        let r0 = max(Int(((box.minY - originY) / cell).rounded(.down)), 0)
        let r1 = min(Int(((box.maxY - originY) / cell).rounded(.up)), rows - 1)
        guard c0 <= c1, r0 <= r1 else { return [] }
        var result: [Int] = []
        for row in r0...r1 {
            for column in c0...c1 {
                let index = row * columns + column
                if box.contains(center(of: index)) { result.append(index) }
            }
        }
        return result
    }

    /// True when the whole box is on the floor: its corners are inside the
    /// room and no wall cuts through it (which matters for L-shaped rooms).
    func containsBox(_ box: Box) -> Bool {
        let inner = box.expanded(by: -0.5)
        guard inner.width > 0, inner.height > 0 else { return false }
        for corner in inner.corners where !Self.polygonContains(corner, corners: corners) {
            return false
        }
        let count = corners.count
        for i in 0..<count {
            if Self.segment(corners[i], corners[(i + 1) % count], crosses: inner) { return false }
        }
        return true
    }

    /// Squares where a person can stand with `halfWidth` of clear space
    /// on every side: the center line of every possible walking path.
    func walkableCells(blockedBy boxes: [Box], halfWidth: Double) -> [Bool] {
        // 1. Which squares are blocked (outside the room or under furniture).
        var blocked = inside.map { !$0 }
        for box in boxes {
            for index in cells(in: box.expanded(by: cell / 2)) { blocked[index] = true }
        }
        // 2. A running total of blocked squares, so "is anything blocked
        // near here?" is answered with four lookups instead of a loop.
        let w = columns + 1
        var sum = [Int](repeating: 0, count: w * (rows + 1))
        for row in 0..<rows {
            for column in 0..<columns {
                sum[(row + 1) * w + column + 1] = (blocked[row * columns + column] ? 1 : 0)
                    + sum[row * w + column + 1] + sum[(row + 1) * w + column] - sum[row * w + column]
            }
        }
        // 3. A square is walkable if nothing is blocked within reach.
        let reach = max(Int((halfWidth / cell).rounded()), 1)
        var walkable = [Bool](repeating: false, count: columns * rows)
        for row in 0..<rows {
            for column in 0..<columns where !blocked[row * columns + column] {
                let r0 = row - reach, r1 = row + reach, c0 = column - reach, c1 = column + reach
                guard r0 >= 0, c0 >= 0, r1 < rows, c1 < columns else { continue }
                let total = sum[(r1 + 1) * w + c1 + 1] - sum[r0 * w + c1 + 1] - sum[(r1 + 1) * w + c0] + sum[r0 * w + c0]
                walkable[row * columns + column] = total == 0
            }
        }
        return walkable
    }

    /// Every walkable square connected to the starting squares.
    func flood(from starts: [Int], through walkable: [Bool]) -> [Bool] {
        var reached = [Bool](repeating: false, count: walkable.count)
        var queue = starts
        for start in starts { reached[start] = true }
        var head = 0
        while head < queue.count {
            let index = queue[head]
            head += 1
            let row = index / columns, column = index % columns
            for (dr, dc) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
                let r = row + dr, c = column + dc
                guard r >= 0, r < rows, c >= 0, c < columns else { continue }
                let next = r * columns + c
                if walkable[next] && !reached[next] {
                    reached[next] = true
                    queue.append(next)
                }
            }
        }
        return reached
    }

    // MARK: Geometry helpers

    /// Ray casting: count how many walls a line to the right crosses.
    static func polygonContains(_ p: Point2D, corners: [Point2D]) -> Bool {
        var inside = false
        var j = corners.count - 1
        for i in 0..<corners.count {
            let a = corners[i], b = corners[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// True when any part of segment a–b passes through the box's inside
    /// (Liang–Barsky clipping).
    static func segment(_ a: Point2D, _ b: Point2D, crosses box: Box) -> Bool {
        var t0 = 0.0, t1 = 1.0
        let dx = b.x - a.x, dy = b.y - a.y
        for (p, q) in [(-dx, a.x - box.minX), (dx, box.maxX - a.x), (-dy, a.y - box.minY), (dy, box.maxY - a.y)] {
            if p == 0 {
                if q <= 0 { return false }
            } else {
                let t = q / p
                if p < 0 { t0 = max(t0, t) } else { t1 = min(t1, t) }
                if t0 >= t1 { return false }
            }
        }
        return t1 - t0 > 1e-6
    }
}
