import Foundation

// The layout engine works on these plain values, not on the SwiftData
// models, so it can run off the main thread and be unit-tested without a
// database. All lengths are centimeters.

/// The room as the engine sees it: its outline and its doors, windows, and
/// outlets.
struct LayoutRoom: Sendable {
    /// Clockwise on screen, like `Room.corners`.
    var corners: [Point2D]
    var features: [FixedFeature]

    init(corners: [Point2D], features: [FixedFeature] = []) {
        self.corners = PolygonGeometry.clockwise(corners)
        self.features = features
    }
}

/// One piece of furniture to place.
struct LayoutItem: Sendable, Identifiable {
    var id: UUID
    var type: ItemType
    var name: String
    var width: Double
    var depth: Double
    var height: Double
    /// Fixed items keep their current spot and are never moved.
    var isFixed: Bool = false
    /// Where it is now, if the person has a chosen layout. Used to keep
    /// moves small, and to say what stays and what moves.
    var current: ItemPlacement?
}

/// Which way an item's front faces. Rotation 0 faces down the screen (the
/// item stands against the top wall); each step of 90 turns it clockwise.
enum Facing {
    /// Unit vector pointing out of the item's front.
    static func front(_ rotation: Int) -> Point2D {
        switch ((rotation % 360) + 360) % 360 {
        case 90: return Point2D(x: -1, y: 0)
        case 180: return Point2D(x: 0, y: -1)
        case 270: return Point2D(x: 1, y: 0)
        default: return Point2D(x: 0, y: 1)
        }
    }

    /// The rotation whose front points closest to `direction`.
    static func rotation(facing direction: Point2D) -> Int {
        if abs(direction.x) > abs(direction.y) {
            return direction.x > 0 ? 270 : 90
        }
        return direction.y < 0 ? 180 : 0
    }
}

/// An upright rectangle on the floor plan. Because items only turn in
/// steps of 90°, every footprint and clearance zone is one of these.
struct Box: Equatable, Sendable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    init(center: Point2D, width: Double, height: Double) {
        self.init(
            minX: center.x - width / 2,
            minY: center.y - height / 2,
            maxX: center.x + width / 2,
            maxY: center.y + height / 2
        )
    }

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var area: Double { max(width, 0) * max(height, 0) }
    var center: Point2D { Point2D(x: (minX + maxX) / 2, y: (minY + maxY) / 2) }
    var corners: [Point2D] {
        [Point2D(x: minX, y: minY), Point2D(x: maxX, y: minY), Point2D(x: maxX, y: maxY), Point2D(x: minX, y: maxY)]
    }

    /// True when the two boxes share some area (touching edges do not count).
    func overlaps(_ other: Box) -> Bool {
        minX < other.maxX - 0.01 && other.minX < maxX - 0.01
            && minY < other.maxY - 0.01 && other.minY < maxY - 0.01
    }

    func contains(_ p: Point2D) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }

    func expanded(by amount: Double) -> Box {
        Box(minX: minX - amount, minY: minY - amount, maxX: maxX + amount, maxY: maxY + amount)
    }

    /// Distance from the box to a point (zero inside).
    func distance(to p: Point2D) -> Double {
        let dx = max(minX - p.x, 0, p.x - maxX)
        let dy = max(minY - p.y, 0, p.y - maxY)
        return hypot(dx, dy)
    }
}

// MARK: - Item placed in a room

/// An item at a spot, with the shapes the rules check.
struct PlacedItem: Sendable {
    var item: LayoutItem
    var placement: ItemPlacement

    var center: Point2D { Point2D(x: placement.x, y: placement.y) }
    var front: Point2D { Facing.front(placement.rotation) }

    /// The floor the item covers. Turned 90° or 270°, width and depth swap.
    var footprint: Box {
        let sideways = placement.rotation % 180 != 0
        return Box(
            center: center,
            width: sideways ? item.depth : item.width,
            height: sideways ? item.width : item.depth
        )
    }

    /// Space that must stay open in front of the item: to sit down, pull
    /// out a chair, or open a drawer. Nil for items that need none.
    var clearance: Box? {
        let depth = item.type.frontClearance(height: item.height)
        guard depth > 0 else { return nil }
        let box = footprint
        let f = front
        if f.y > 0 { return Box(minX: box.minX, minY: box.maxY, maxX: box.maxX, maxY: box.maxY + depth) }
        if f.y < 0 { return Box(minX: box.minX, minY: box.minY - depth, maxX: box.maxX, maxY: box.minY) }
        if f.x > 0 { return Box(minX: box.maxX, minY: box.minY, maxX: box.maxX + depth, maxY: box.maxY) }
        return Box(minX: box.minX - depth, minY: box.minY, maxX: box.minX, maxY: box.maxY)
    }
}

// MARK: - What each kind of item needs

extension ItemType {
    /// Open floor needed in front, in cm. Numbers follow common interior
    /// design guidance (for example 75–90 cm to pull out a desk chair).
    func frontClearance(height: Double) -> Double {
        switch self {
        case .sofa: return 45
        case .bed: return 60
        case .desk: return 75
        case .table: return height < 55 ? 0 : 75  // a coffee table needs none
        case .chair: return 40
        case .dresser: return 75
        case .shelf: return 60
        case .tvStand: return 0
        case .lamp, .rug: return 0
        case .other: return 45
        }
    }

    /// Things people sit on, which should face the focal point.
    var isSeating: Bool { self == .sofa || self == .chair }

    /// Things that work best near an outlet.
    var needsPower: Bool { self == .lamp || self == .tvStand || self == .desk }

    /// Big pieces that belong against a wall.
    var wantsWall: Bool {
        switch self {
        case .sofa, .bed, .desk, .dresser, .shelf, .tvStand: return true
        default: return false
        }
    }

    /// Placed first, largest and most constrained first.
    var placementPriority: Int {
        switch self {
        case .bed: return 0
        // The TV goes first so the sofa can turn to face it.
        case .tvStand: return 1
        case .sofa: return 2
        case .desk, .dresser, .shelf: return 3
        case .table: return 4
        case .chair, .other: return 5
        case .lamp: return 6
        case .rug: return 7
        }
    }
}

extension LayoutItem {
    /// A low table is treated as a coffee table, a tall one as a dining
    /// table or desk-height table.
    var isCoffeeTable: Bool { type == .table && height < 55 }

    /// Tall enough to block light if put in front of a window.
    var isTall: Bool { height > 100 && type != .lamp }

    /// Rugs lie under other things, so they never count as overlapping.
    var liesFlat: Bool { type == .rug }
}

// MARK: - Repeatable randomness

/// A small random number generator that always gives the same numbers for
/// the same seed, so the engine returns the same layouts for the same room
/// (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
