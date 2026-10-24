import Foundation

/// One suggested arrangement.
struct LayoutSuggestion: Sendable, Identifiable {
    let id = UUID()
    /// A short description, like "Seating faces the window".
    var label: String
    var placements: [ItemPlacement]
    /// Items that did not fit anywhere.
    var leftOut: [UUID]
    /// 0 to 100; higher is better.
    var score: Double
    var breakdown: LayoutScore
}

/// How a layout scored on each goal, each from 0 to 1.
struct LayoutScore: Sendable {
    var placed = 0.0
    var walkability = 0.0
    var balance = 0.0
    var facing = 0.0
    var outlets = 0.0
    var fewMoves = 0.0

    /// Weights add to 100. Fitting everything matters most.
    var total: Double {
        placed * 40 + walkability * 15 + balance * 10 + facing * 15 + outlets * 10 + fewMoves * 10
    }
}

/// Arranges furniture in a room with rules, not AI: fast, free, works
/// offline, and gives the same answer for the same room and seed.
///
/// How it works:
/// 1. Build many candidate layouts. Each one places the items one at a
///    time, biggest first, choosing among the best few spots for each item
///    with a little randomness, so the candidates differ.
/// 2. Throw out any spot that breaks a hard rule (see `LayoutRules`).
/// 3. Score every candidate and keep the best few that really differ.
enum LayoutEngine {
    struct Options: Sendable {
        var seed: UInt64 = 42
        var candidates = 60
        var maxResults = 5
        /// A safety net for very large rooms: stop building candidates
        /// after this long, in seconds. Normal rooms finish well before it,
        /// so the same input always gives the same layouts.
        var timeBudget = 3.0
    }

    static func suggest(room: LayoutRoom, items: [LayoutItem], options: Options = Options()) -> [LayoutSuggestion] {
        guard room.corners.count >= 3, !items.isEmpty else { return [] }
        let rules = LayoutRules(room: room)
        var rng = SeededGenerator(seed: options.seed)
        let started = Date()

        // Lots of furniture means each candidate takes longer, so build
        // fewer of them. (Depends only on the input, so results stay
        // repeatable.)
        let candidateCount = items.count > 10 ? max(12, options.candidates * 10 / items.count) : options.candidates

        var candidates: [LayoutSuggestion] = []
        for attempt in 0..<candidateCount {
            // Always build a few candidates, then respect the time budget.
            if attempt >= 8, Date().timeIntervalSince(started) > options.timeBudget { break }
            // The first candidate is the least random one.
            let jitter = attempt == 0 ? 0.0 : 1.0
            let placed = buildCandidate(items: items, rules: rules, jitter: jitter, rng: &rng)
            candidates.append(score(placed, items: items, rules: rules))
        }

        // Where things are now is an option too, if it still follows the
        // rules, so the person can see how it compares.
        if items.allSatisfy({ $0.current != nil }) {
            let current = items.map { PlacedItem(item: $0, placement: $0.current!) }
            if rules.problems(in: current).isEmpty {
                candidates.append(score(current, items: items, rules: rules))
            }
        }

        let picked = pickDistinct(candidates.sorted { $0.score > $1.score }, count: options.maxResults)
        return label(picked, items: items, rules: rules)
    }

    // MARK: Building one candidate

    private static func buildCandidate(
        items: [LayoutItem],
        rules: LayoutRules,
        jitter: Double,
        rng: inout SeededGenerator
    ) -> [PlacedItem] {
        var placed: [PlacedItem] = []

        // Fixed items stay exactly where they are.
        for item in items where item.isFixed {
            if let current = item.current {
                placed.append(PlacedItem(item: item, placement: current))
            }
        }

        // Then the rest, most important first, with ties in random order.
        let order = items
            .filter { !$0.isFixed || $0.current == nil }
            .map { ($0, Double($0.type.placementPriority) + Double.random(in: 0..<0.9, using: &rng) * jitter) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)

        for item in order {
            let options = spots(for: item, placed: placed, rules: rules)
                .filter { rules.quickProblems($0.0, among: placed).isEmpty }
                .map { ($0.0, $0.1 + Double.random(in: 0..<2.5, using: &rng) * jitter) }
                .sorted { $0.1 > $1.1 }

            // Take the best spot that still leaves a walking path; only
            // the top 25 are tried, to stay fast.
            for (spot, _) in options.prefix(25) {
                let trial = placed + [spot]
                if rules.unreachableItems(in: trial).isEmpty {
                    placed = trial
                    break
                }
            }
        }
        return placed
    }

    /// The best spot for one more item among furniture that stays put, or
    /// nil if there is none. Used by the catalog's "does it fit?" check.
    static func findSpot(for item: LayoutItem, among placed: [PlacedItem], rules: LayoutRules) -> PlacedItem? {
        let options = spots(for: item, placed: placed, rules: rules)
            .filter { rules.quickProblems($0.0, among: placed).isEmpty }
            .sorted { $0.1 > $1.1 }
        // Unlike building a layout, try every spot: a "no" must be sure.
        return options.first { rules.unreachableItems(in: placed + [$0.0]).isEmpty }?.0
    }

    /// Spots worth trying for an item, each with a "how good is this
    /// spot" number (higher is better).
    private static func spots(for item: LayoutItem, placed: [PlacedItem], rules: LayoutRules) -> [(PlacedItem, Double)] {
        var result: [PlacedItem] = []

        if item.type.wantsWall {
            result += wallSpots(for: item, rules: rules)
        }
        if item.isCoffeeTable, let sofa = placed.first(where: { $0.item.type == .sofa }) {
            // About 45 cm in front of the sofa, the usual reach.
            let gap = sofa.item.depth / 2 + 45 + item.depth / 2
            result.append(spot(item, at: offset(sofa.center, sofa.front, gap), rotation: sofa.placement.rotation))
        }
        if item.type == .chair, let desk = placed.first(where: { $0.item.type == .desk }),
           !placed.contains(where: { $0.item.type == .chair && $0.center.distance(to: desk.center) < 120 }) {
            // A desk chair, pulled up to the desk and facing it.
            let gap = desk.item.depth / 2 + item.depth / 2 + 5
            result.append(spot(item, at: offset(desk.center, desk.front, gap), rotation: (desk.placement.rotation + 180) % 360))
        }
        if item.type == .lamp {
            result += lampSpots(for: item, placed: placed)
        }
        if result.isEmpty || !item.type.wantsWall {
            result += openFloorSpots(for: item, placed: placed, rules: rules)
        }

        return result.map { ($0, appeal(of: $0, placed: placed, rules: rules)) }
    }

    /// Positions with the item's back against a straight, upright wall,
    /// every 15 cm along it.
    private static func wallSpots(for item: LayoutItem, rules: LayoutRules) -> [PlacedItem] {
        let corners = rules.room.corners
        var result: [PlacedItem] = []
        for i in corners.indices {
            let a = corners[i], b = corners[(i + 1) % corners.count]
            let length = PlanGeometry.distance(a, b)
            let horizontal = abs(a.y - b.y) < 1, vertical = abs(a.x - b.x) < 1
            guard length >= item.width, horizontal || vertical else { continue }
            let along = Point2D(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
            let inward = Point2D(x: -along.y, y: along.x)
            let rotation = Facing.rotation(facing: inward)
            var t = item.width / 2
            while t <= length - item.width / 2 + 0.01 {
                let onWall = Point2D(x: a.x + along.x * t, y: a.y + along.y * t)
                result.append(spot(item, at: offset(onWall, inward, item.depth / 2 + 1), rotation: rotation))
                t += 15
            }
        }
        return result
    }

    /// A grid of spots across the floor. Seats turn to face the focal point;
    /// other things try both directions.
    private static func openFloorSpots(for item: LayoutItem, placed: [PlacedItem], rules: LayoutRules) -> [PlacedItem] {
        let grid = rules.grid
        // About 40 spots across, never closer than 25 cm.
        let step = max(25, Double(max(grid.columns, grid.rows)) * grid.cell / 40)
        let focus = focalPoint(placed: placed, rules: rules)
        var result: [PlacedItem] = []
        var y = grid.originY + step / 2
        while y < grid.originY + Double(grid.rows) * grid.cell {
            var x = grid.originX + step / 2
            while x < grid.originX + Double(grid.columns) * grid.cell {
                let center = Point2D(x: x, y: y)
                if item.type.isSeating, let focus {
                    let toward = Point2D(x: focus.x - x, y: focus.y - y)
                    result.append(spot(item, at: center, rotation: Facing.rotation(facing: toward)))
                } else {
                    result.append(spot(item, at: center, rotation: 0))
                    result.append(spot(item, at: center, rotation: 90))
                }
                x += step
            }
            y += step
        }
        return result
    }

    /// Lamps go beside a sofa, bed, or desk.
    private static func lampSpots(for item: LayoutItem, placed: [PlacedItem]) -> [PlacedItem] {
        var result: [PlacedItem] = []
        for anchor in placed where [.sofa, .bed, .desk, .chair].contains(anchor.item.type) {
            let box = anchor.footprint
            let half = max(item.width, item.depth) / 2 + 2
            let sides = [
                Point2D(x: box.minX - half, y: box.center.y), Point2D(x: box.maxX + half, y: box.center.y),
                Point2D(x: box.center.x, y: box.minY - half), Point2D(x: box.center.x, y: box.maxY + half),
                Point2D(x: box.minX - half, y: box.minY + half), Point2D(x: box.maxX + half, y: box.minY + half),
            ]
            result += sides.map { spot(item, at: $0, rotation: anchor.placement.rotation) }
        }
        return result
    }

    // MARK: How good is one spot

    private static func appeal(of candidate: PlacedItem, placed: [PlacedItem], rules: LayoutRules) -> Double {
        let item = candidate.item
        let center = candidate.center
        var score = 0.0

        switch item.type {
        case .bed:
            // Headboard on a solid wall: no window or door behind it.
            let back = candidate.footprint.expanded(by: 30)
            let blocked = rules.windowZones.contains { $0.overlaps(back) } || rules.doorZones.contains { $0.overlaps(back) }
            score += blocked ? 0 : 4
            // Away from the door feels calmer.
            score += min(nearestDistance(from: center, to: rules.doorZones.map(\.center)) / 150, 2)
        case .sofa, .chair:
            if let focus = focalPoint(placed: placed, rules: rules) {
                score += 3 * facing(candidate, toward: focus)
                let distance = center.distance(to: focus)
                score += (150...400).contains(distance) ? 1.5 : 0
            }
            if item.type == .chair, let sofa = placed.first(where: { $0.item.type == .sofa }) {
                // Conversation grouping: close to the sofa.
                let distance = center.distance(to: sofa.center)
                score += distance < 260 ? 2 : 0
            }
        case .tvStand:
            // Not on a window wall (glare), with a long open view in front
            // for the sofa to sit across from.
            let behind = candidate.footprint.expanded(by: 30)
            score += rules.windowZones.contains { $0.overlaps(behind) } ? 0 : 3
            score += min(openDistance(from: candidate, rules: rules), 400) / 100
            if let sofa = placed.first(where: { $0.item.type == .sofa }) {
                score += 3 * facing(candidate, toward: sofa.center)
            }
        case .desk:
            // Near daylight.
            score += max(0, 4 - nearestDistance(from: center, to: rules.windowCenters) / 75)
        case .dresser, .shelf:
            let behind = candidate.footprint.expanded(by: 30)
            score += rules.windowZones.contains { $0.overlaps(behind) } ? 0 : 1.5
        case .table:
            if item.isCoffeeTable, let sofa = placed.first(where: { $0.item.type == .sofa }) {
                // As close as possible to the spot just in front of the sofa.
                let ideal = offset(sofa.center, sofa.front, sofa.item.depth / 2 + 45 + item.depth / 2)
                score += max(0, 6 - center.distance(to: ideal) / 30)
                score += candidate.placement.rotation % 180 == sofa.placement.rotation % 180 ? 1 : 0
            } else if !item.isCoffeeTable {
                // A dining table sits toward the middle of the open floor.
                score += max(0, 3 - center.distance(to: rules.middle) / 100)
            }
        case .lamp:
            score += 1
        case .rug:
            if let seats = seatingCenter(placed) {
                score += max(0, 4 - center.distance(to: seats) / 50)
            }
        case .other:
            break
        }

        if item.type.needsPower, !rules.outlets.isEmpty {
            score += max(0, 2 - nearestDistance(from: center, to: rules.outlets) / 100)
        }
        if let current = item.current {
            // Small moves are easier to try.
            score += max(0, 1.5 - Point2D(x: current.x, y: current.y).distance(to: center) / 150)
        }
        return score
    }

    // MARK: Scoring a whole layout

    static func score(_ placed: [PlacedItem], items: [LayoutItem], rules: LayoutRules) -> LayoutSuggestion {
        var s = LayoutScore()
        s.placed = Double(placed.count) / Double(max(items.count, 1))
        s.walkability = rules.walkableShare(of: placed)

        // Balance: furniture spread around the room, not piled on one side.
        let middle = rules.middle
        let weight = placed.map { $0.footprint.area }.reduce(0, +)
        if weight > 0 {
            let cx = placed.map { $0.center.x * $0.footprint.area }.reduce(0, +) / weight
            let cy = placed.map { $0.center.y * $0.footprint.area }.reduce(0, +) / weight
            let reach = max(rules.grid.columns, rules.grid.rows).double * rules.grid.cell / 2
            s.balance = max(0, 1 - Point2D(x: cx, y: cy).distance(to: middle) / reach)
        } else {
            s.balance = 1
        }

        // Seats facing the focal point.
        let seats = placed.filter { $0.item.type.isSeating && !$0.isDeskChair(among: placed) }
        if let focus = focalPoint(placed: placed, rules: rules), !seats.isEmpty {
            s.facing = seats.map { facing($0, toward: focus) }.reduce(0, +) / Double(seats.count)
        } else {
            s.facing = 1
        }

        // Things that need power, close to an outlet.
        let powered = placed.filter { $0.item.type.needsPower }
        if rules.outlets.isEmpty || powered.isEmpty {
            s.outlets = 1
        } else {
            s.outlets = powered.map { max(0, 1 - max(0, nearestDistance(from: $0.center, to: rules.outlets) - 100) / 250) }
                .reduce(0, +) / Double(powered.count)
        }

        // Fewer and shorter moves from where things are now.
        let moved = placed.compactMap { p -> Double? in
            guard let current = p.item.current else { return nil }
            return Point2D(x: current.x, y: current.y).distance(to: p.center)
        }
        s.fewMoves = moved.isEmpty ? 1 : max(0, 1 - moved.reduce(0, +) / Double(moved.count) / 300)

        let placedIDs = Set(placed.map(\.item.id))
        return LayoutSuggestion(
            label: "",
            placements: placed.map(\.placement),
            leftOut: items.map(\.id).filter { !placedIDs.contains($0) },
            score: s.total,
            breakdown: s
        )
    }

    // MARK: Picking distinct layouts

    /// The best layouts that differ from each other by a real amount, not
    /// the same arrangement nudged by a few centimeters.
    private static func pickDistinct(_ sorted: [LayoutSuggestion], count: Int) -> [LayoutSuggestion] {
        var picked: [LayoutSuggestion] = []
        func take(from pool: [LayoutSuggestion], upTo limit: Int) {
            for candidate in pool where picked.count < limit {
                if picked.allSatisfy({ difference(candidate, $0) >= 40 }) {
                    picked.append(candidate)
                }
            }
        }
        // First, only layouts that fit as many items as the best one does,
        // so a layout that leaves something out is never shown when a
        // complete one exists...
        let fewestLeftOut = sorted.map(\.leftOut.count).min() ?? 0
        take(from: sorted.filter { $0.leftOut.count == fewestLeftOut }, upTo: count)
        // ...then, if that gives fewer than 3, top up with the rest.
        take(from: sorted, upTo: max(min(3, count), picked.count))
        return picked
    }

    /// Average distance items moved between two layouts, in cm. An item
    /// turned around or placed in only one of them counts as a big change.
    static func difference(_ a: LayoutSuggestion, _ b: LayoutSuggestion) -> Double {
        let aByID = Dictionary(uniqueKeysWithValues: a.placements.map { ($0.itemID, $0) })
        let bByID = Dictionary(uniqueKeysWithValues: b.placements.map { ($0.itemID, $0) })
        let ids = Set(aByID.keys).union(bByID.keys)
        guard !ids.isEmpty else { return 0 }
        var total = 0.0
        for id in ids {
            if let p = aByID[id], let q = bByID[id] {
                total += hypot(p.x - q.x, p.y - q.y) + (p.rotation == q.rotation ? 0 : 60)
            } else {
                total += 200
            }
        }
        return total / Double(ids.count)
    }

    // MARK: Labels

    /// Gives each layout a short name for what makes it different.
    private static func label(_ layouts: [LayoutSuggestion], items: [LayoutItem], rules: LayoutRules) -> [LayoutSuggestion] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var used = Set<String>()
        let mostOpen = layouts.map(\.breakdown.walkability).max() ?? 0
        let fewestMoves = layouts.map(\.breakdown.fewMoves).max() ?? 0
        let hasCurrent = items.contains { $0.current != nil }

        return layouts.enumerated().map { index, layout in
            let placed = layout.placements.compactMap { p in byID[p.itemID].map { PlacedItem(item: $0, placement: p) } }
            var ideas: [String] = []

            let seats = placed.filter { $0.item.type.isSeating && !$0.isDeskChair(among: placed) }
            if let tv = placed.first(where: { $0.item.type == .tvStand }), !seats.isEmpty,
               seats.allSatisfy({ facing($0, toward: tv.center) > 0.6 }) {
                ideas.append("Seating faces the TV")
            }
            if !rules.windowCenters.isEmpty, !seats.isEmpty,
               seats.allSatisfy({ s in rules.windowCenters.contains { facing(s, toward: $0) > 0.6 } }) {
                ideas.append("Seating faces the window")
            }
            if let desk = placed.first(where: { $0.item.type == .desk }),
               nearestDistance(from: desk.center, to: rules.windowCenters) < 160 {
                ideas.append("Desk by the window")
            }
            if let bed = placed.first(where: { $0.item.type == .bed }) {
                let back = bed.footprint.expanded(by: 30)
                if !rules.windowZones.contains(where: { $0.overlaps(back) }) {
                    ideas.append("Bed on a solid wall")
                }
            }
            if seats.count >= 2, let sofa = seats.first(where: { $0.item.type == .sofa }),
               seats.filter({ $0.item.type == .chair }).allSatisfy({ $0.center.distance(to: sofa.center) < 260 }) {
                ideas.append("Cozy conversation area")
            }
            if hasCurrent, layout.breakdown.fewMoves >= fewestMoves - 0.001 {
                ideas.append("Fewest moves")
            }
            if layout.breakdown.walkability >= mostOpen - 0.001 {
                ideas.append("Most open floor")
            }

            var copy = layout
            copy.label = ideas.first { !used.contains($0) } ?? "Option \(index + 1)"
            used.insert(copy.label)
            return copy
        }
    }

    // MARK: Small helpers

    /// What seats should face: the TV if there is one, else a window.
    static func focalPoint(placed: [PlacedItem], rules: LayoutRules) -> Point2D? {
        if let tv = placed.first(where: { $0.item.type == .tvStand }) { return tv.center }
        return rules.windowCenters.first
    }

    /// The middle of the seats, where a rug or coffee table belongs.
    private static func seatingCenter(_ placed: [PlacedItem]) -> Point2D? {
        let seats = placed.filter { $0.item.type.isSeating }
        guard !seats.isEmpty else { return nil }
        return Point2D(
            x: seats.map(\.center.x).reduce(0, +) / Double(seats.count),
            y: seats.map(\.center.y).reduce(0, +) / Double(seats.count)
        )
    }

    /// 1 when the item's front points straight at the target, 0 when it
    /// points sideways or away.
    static func facing(_ item: PlacedItem, toward target: Point2D) -> Double {
        let dx = target.x - item.center.x, dy = target.y - item.center.y
        let length = hypot(dx, dy)
        guard length > 1 else { return 1 }
        return max(0, (item.front.x * dx + item.front.y * dy) / length)
    }

    /// How far you can see straight out from an item's front before a
    /// wall, in cm (checked every 10 cm, up to 6 m).
    private static func openDistance(from item: PlacedItem, rules: LayoutRules) -> Double {
        let box = item.footprint
        let f = item.front
        let start = Point2D(x: box.center.x + f.x * box.width / 2, y: box.center.y + f.y * box.height / 2)
        var distance = 0.0
        while distance < 600 {
            let p = offset(start, f, distance + 10)
            if !FloorGrid.polygonContains(p, corners: rules.room.corners) { break }
            distance += 10
        }
        return distance
    }

    private static func nearestDistance(from p: Point2D, to points: [Point2D]) -> Double {
        points.map { p.distance(to: $0) }.min() ?? 1_000
    }

    private static func spot(_ item: LayoutItem, at center: Point2D, rotation: Int) -> PlacedItem {
        PlacedItem(item: item, placement: ItemPlacement(itemID: item.id, x: center.x, y: center.y, rotation: rotation))
    }

    private static func offset(_ p: Point2D, _ direction: Point2D, _ distance: Double) -> Point2D {
        Point2D(x: p.x + direction.x * distance, y: p.y + direction.y * distance)
    }
}

extension PlacedItem {
    /// A chair pulled up to a desk faces the desk, not the TV.
    func isDeskChair(among placed: [PlacedItem]) -> Bool {
        item.type == .chair && placed.contains { $0.item.type == .desk && $0.center.distance(to: center) < 120 }
    }
}

extension Point2D {
    func distance(to other: Point2D) -> Double {
        PlanGeometry.distance(self, other)
    }
}

extension PolygonGeometry {
    /// The balance point of the floor.
    static func centroid(_ corners: [Point2D]) -> Point2D {
        let area = signedArea(corners)
        guard abs(area) > 0.001 else {
            let n = Double(max(corners.count, 1))
            return Point2D(x: corners.map(\.x).reduce(0, +) / n, y: corners.map(\.y).reduce(0, +) / n)
        }
        var cx = 0.0, cy = 0.0
        for i in corners.indices {
            let a = corners[i], b = corners[(i + 1) % corners.count]
            let cross = a.x * b.y - b.x * a.y
            cx += (a.x + b.x) * cross
            cy += (a.y + b.y) * cross
        }
        return Point2D(x: cx / (6 * area), y: cy / (6 * area))
    }
}

private extension Int {
    var double: Double { Double(self) }
}
