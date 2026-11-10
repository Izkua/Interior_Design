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
    /// Pieces that belong together sit together (see `LayoutEngine.grouping`).
    var grouping = 0.0

    /// Weights add to 100. Fitting everything matters most, then keeping
    /// the seating group together.
    var total: Double {
        placed * 35 + walkability * 10 + balance * 5 + facing * 10 + outlets * 5 + fewMoves * 10 + grouping * 25
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
///
/// Pieces that belong together are offered spots together: the coffee
/// table in front of the sofa, armchairs beside it facing in, a floor lamp
/// at the end of a seat. Anywhere else is only a fallback.
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
            // (With furniture groups, a candidate for 30 pieces can take
            // most of a second in a debug build, so only 3 are guaranteed.)
            if attempt >= 3, Date().timeIntervalSince(started) > options.timeBudget { break }
            // The first candidate is the least random one.
            let jitter = attempt == 0 ? 0.0 : 1.0
            let placed = buildCandidate(items: items, rules: rules, jitter: jitter, rng: &rng)
            candidates.append(score(placed, items: items, rules: rules))
        }

        // Where things are now is an option too, if it still follows the
        // rules, so the person can see how it compares.
        var current: LayoutSuggestion?
        if items.allSatisfy({ $0.current != nil }) {
            let placed = items.map { PlacedItem(item: $0, placement: $0.current!) }
            if rules.problems(in: placed).isEmpty {
                current = score(placed, items: items, rules: rules)
                candidates.append(current!)
            }
        }

        var picked = pickDistinct(candidates.sorted { $0.score > $1.score }, count: options.maxResults)
        if let current {
            keep(current, in: &picked, count: options.maxResults)
        }
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

        for (index, item) in order.enumerated() {
            let toCome = Array(order[(index + 1)...])
            let options = spots(for: item, placed: placed, toCome: toCome, rules: rules)
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
        let options = spots(for: item, placed: placed, toCome: [], rules: rules)
            .filter { rules.quickProblems($0.0, among: placed).isEmpty }
            .sorted { $0.1 > $1.1 }
        // Unlike building a layout, try every spot: a "no" must be sure.
        return options.first { rules.unreachableItems(in: placed + [$0.0]).isEmpty }?.0
    }

    /// How much worse a fallback spot scores than a preferred one, so it
    /// is only used when no preferred spot follows the rules.
    private static let fallbackPenalty = 20.0

    /// Spots worth trying for an item, each with a "how good is this
    /// spot" number (higher is better). `toCome` are the items still to
    /// place, so a sofa can leave room for its coffee table and armchairs.
    private static func spots(for item: LayoutItem, placed: [PlacedItem], toCome: [LayoutItem], rules: LayoutRules) -> [(PlacedItem, Double)] {
        var preferred: [PlacedItem] = []

        if item.type.wantsWall {
            preferred += wallSpots(for: item, rules: rules)
        }
        if item.isCoffeeTable, let sofa = mainSofa(placed) {
            preferred += coffeeTableSpots(for: item, sofa: sofa)
        }
        if item.type == .chair {
            if !item.isLoungeChair, let table = tableWithoutChair(placed) {
                preferred += pullUpSpots(for: item, at: table)
            } else if let sofa = mainSofa(placed) {
                preferred += conversationSpots(for: item, sofa: sofa, placed: placed)
            }
        }
        if item.type == .lamp {
            preferred += lampSpots(for: item, placed: placed)
        }

        var fallback: [PlacedItem] = []
        if preferred.isEmpty {
            preferred = openFloorSpots(for: item, placed: placed, rules: rules)
        } else if !item.type.wantsWall {
            fallback = openFloorSpots(for: item, placed: placed, rules: rules)
        }

        var scored = preferred.map { ($0, appeal(of: $0, placed: placed, rules: rules)) }
            + fallback.map { ($0, appeal(of: $0, placed: placed, rules: rules) - fallbackPenalty) }
        if item.type == .sofa, mainSofa(placed) == nil {
            // Look ahead from every spot that follows the rules.
            let tvComing = toCome.contains { $0.type == .tvStand }
            scored = scored.filter { rules.quickProblems($0.0, among: placed).isEmpty }.map { spot, score in
                var bonus = 8 * roomForGroup(around: spot, placed: placed, toCome: toCome, rules: rules)
                if tvComing, facesSolidWall(spot, rules: rules) { bonus += 5 }
                return (spot, score + bonus)
            }
        }
        return scored
    }

    /// Centered in front of the sofa with a 45–50 cm gap, the usual reach,
    /// or nudged a little to one side.
    private static func coffeeTableSpots(for item: LayoutItem, sofa: PlacedItem) -> [PlacedItem] {
        let side = sideways(sofa.front)
        var result: [PlacedItem] = []
        for gap in [45.0, 50.0] {
            let middle = offset(sofa.center, sofa.front, sofa.item.depth / 2 + gap + item.depth / 2)
            for shift in [0.0, -15, 15] {
                result.append(spot(item, at: offset(middle, side, shift), rotation: sofa.placement.rotation))
            }
        }
        return result
    }

    /// For a sofa spot, the share of its group (coffee table and armchairs
    /// still to place) that would fit around it, 0 to 1. A quick look
    /// ahead: it checks the hard rules but not the full walking path, and
    /// skips chair spots right beside a doorway, which would block the way in.
    static func roomForGroup(around sofa: PlacedItem, placed: [PlacedItem], toCome: [LayoutItem], rules: LayoutRules) -> Double {
        var group = placed + [sofa]
        var wanted = 0, fitted = 0
        if let table = toCome.first(where: \.isCoffeeTable) {
            wanted += 1
            if let spot = coffeeTableSpots(for: table, sofa: sofa).first(where: { rules.quickProblems($0, among: group).isEmpty }) {
                group.append(spot)
                fitted += 1
            }
        }
        for chair in toCome where chair.isLoungeChair {
            wanted += 1
            let tvComing = toCome.contains { $0.type == .tvStand }
            let spot = conversationSpots(for: chair, sofa: sofa, placed: group, tvComing: tvComing).first { spot in
                rules.quickProblems(spot, among: group).isEmpty
                    && !rules.doors.contains { gap(between: $0.approach, and: spot.footprint) < 2 * LayoutRules.pathHalfWidth }
            }
            if let spot {
                group.append(spot)
                fitted += 1
            }
        }
        return wanted == 0 ? 1 : Double(fitted) / Double(wanted)
    }

    /// True when the wall straight ahead of an item has no window near the
    /// middle, so a TV can go there without glare.
    static func facesSolidWall(_ item: PlacedItem, rules: LayoutRules) -> Bool {
        let ahead = offset(item.center, item.front, max(item.footprint.width, item.footprint.height) / 2 + openDistance(from: item, rules: rules))
        return rules.windowCenters.allSatisfy { $0.distance(to: ahead) > 120 }
    }

    /// A desk or dining table that has no chair pulled up to it yet.
    private static func tableWithoutChair(_ placed: [PlacedItem]) -> PlacedItem? {
        placed.first { table in
            (table.item.type == .desk || (table.item.type == .table && !table.item.isCoffeeTable))
                && !placed.contains { $0.item.type == .chair && $0.center.distance(to: table.center) < 120 }
        }
    }

    /// A small chair pulled up to a desk or dining table, facing it.
    private static func pullUpSpots(for item: LayoutItem, at table: PlacedItem) -> [PlacedItem] {
        let gap = table.item.depth / 2 + item.depth / 2 + 5
        var result = [spot(item, at: offset(table.center, table.front, gap), rotation: (table.placement.rotation + 180) % 360)]
        if table.item.type == .table {
            // A dining table can be sat at from either long side.
            result.append(spot(item, at: offset(table.center, table.front, -gap), rotation: table.placement.rotation))
        }
        return result
    }

    /// Spots that make a conversation group with the sofa: beside the
    /// coffee table at either end, facing in, or across from the sofa
    /// facing it when there is no TV in the way (placed, or still to come).
    private static func conversationSpots(for item: LayoutItem, sofa: PlacedItem, placed: [PlacedItem], tvComing: Bool = false) -> [PlacedItem] {
        let f = sofa.front, side = sideways(f)
        let table = placed.first { $0.item.isCoffeeTable }
        let tableHalfWidth = (table?.item.width ?? 110) / 2
        let tableHalfDepth = (table?.item.depth ?? 60) / 2
        // Clear of the space the sofa needs in front, then level with the table.
        let along = sofa.item.depth / 2 + ItemType.sofa.frontClearance(height: sofa.item.height)
        var result: [PlacedItem] = []

        for direction in [1.0, -1.0] {
            let out = Point2D(x: side.x * direction, y: side.y * direction)
            let rotation = Facing.rotation(facing: Point2D(x: -out.x, y: -out.y))
            for gap in [45.0, 60.0] {
                for shift in [0.0, 20, 40, 70] {
                    // Turned to face the table, the chair's width runs along the sofa's front.
                    let forward = offset(sofa.center, f, along + item.width / 2 + shift)
                    result.append(spot(item, at: offset(forward, out, tableHalfWidth + gap + item.depth / 2), rotation: rotation))
                }
            }
        }
        if !tvComing, !placed.contains(where: { $0.item.type == .tvStand }) {
            let across = offset(groupHub(sofa: sofa, placed: placed), f, tableHalfDepth + 45 + item.depth / 2)
            for shift in [0.0, -40, 40] {
                result.append(spot(item, at: offset(across, side, shift), rotation: (sofa.placement.rotation + 180) % 360))
            }
        }
        return result
    }

    /// Lamps go at the end of a seat, a bed, or a desk: flush with its
    /// back, level with its middle, or level with its front.
    private static func lampSpots(for item: LayoutItem, placed: [PlacedItem]) -> [PlacedItem] {
        var result: [PlacedItem] = []
        for anchor in placed where [.sofa, .bed, .desk, .chair].contains(anchor.item.type) {
            let f = anchor.front, side = sideways(f)
            let reach = max(item.width, item.depth) / 2 + 3
            for direction in [1.0, -1.0] {
                for back in [anchor.item.depth / 2 - reach, 0, reach - anchor.item.depth / 2] {
                    let end = offset(anchor.center, side, direction * (anchor.item.width / 2 + reach))
                    result.append(spot(item, at: offset(end, f, -back), rotation: anchor.placement.rotation))
                }
            }
        }
        return result
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

    // MARK: How good is one spot

    private static func appeal(of candidate: PlacedItem, placed: [PlacedItem], rules: LayoutRules) -> Double {
        let item = candidate.item
        let center = candidate.center
        var score = 0.0

        switch item.type {
        case .bed:
            // Headboard on a solid wall: no window or door behind it.
            let back = candidate.footprint.expanded(by: 30)
            let blocked = rules.windowZones.contains { $0.overlaps(back) } || rules.doors.contains { $0.approach.overlaps(back) }
            score += blocked ? 0 : 4
            // Away from the door feels calmer.
            score += min(nearestDistance(from: center, to: rules.doors.map(\.approach.center)) / 150, 2)
        case .chair where item.isLoungeChair && mainSofa(placed) != nil:
            // Part of the conversation group: close to it and facing in.
            let fit = conversationFit(candidate, hub: groupHub(sofa: mainSofa(placed)!, placed: placed))
            score += 6 * fit
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
                // Across from the sofa, each facing the other.
                score += 3 * facing(candidate, toward: sofa.center) + 5 * facing(sofa, toward: candidate.center)
            }
        case .desk:
            // Near daylight.
            score += max(0, 4 - nearestDistance(from: center, to: rules.windowCenters) / 75)
        case .dresser, .shelf:
            let behind = candidate.footprint.expanded(by: 30)
            score += rules.windowZones.contains { $0.overlaps(behind) } ? 0 : 1.5
            // On a free wall, away from the doors.
            score += min(nearestDistance(from: center, to: rules.doors.map(\.approach.center)) / 100, 3)
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
            score += 4 * lampFit(candidate, among: placed)
        case .rug:
            if let seats = seatingCenter(placed) {
                score += max(0, 4 - center.distance(to: seats) / 50)
            }
        default:
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

        // Seats facing the focal point. Armchairs in a group face the
        // sofa instead, which `grouping` scores.
        let sofas = placed.filter { $0.item.type == .sofa }
        let seats = sofas.isEmpty ? placed.filter { $0.item.type.isSeating && !$0.isDeskChair(among: placed) } : sofas
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
        s.grouping = grouping(placed)

        let placedIDs = Set(placed.map(\.item.id))
        return LayoutSuggestion(
            label: "",
            placements: placed.map(\.placement),
            leftOut: items.map(\.id).filter { !placedIDs.contains($0) },
            score: s.total,
            breakdown: s
        )
    }

    // MARK: Grouping

    /// How well pieces that belong together sit together, 0 to 1: half the
    /// average of every check that applies to this room's furniture, half
    /// the worst one, so one piece off on its own pulls the score down.
    static func grouping(_ placed: [PlacedItem]) -> Double {
        var checks: [Double] = []
        if let sofa = mainSofa(placed) {
            if let table = placed.first(where: { $0.item.isCoffeeTable }) {
                checks.append(coffeeTableFit(table, sofa: sofa))
            }
            let hub = groupHub(sofa: sofa, placed: placed)
            for chair in placed where chair.item.isLoungeChair {
                checks.append(conversationFit(chair, hub: hub))
            }
            if let tv = placed.first(where: { $0.item.type == .tvStand }) {
                checks.append(facing(tv, toward: sofa.center) * facing(sofa, toward: tv.center))
            }
        }
        for lamp in placed where lamp.item.type == .lamp {
            checks.append(lampFit(lamp, among: placed))
        }
        guard let worst = checks.min() else { return 1 }
        return (checks.reduce(0, +) / Double(checks.count) + worst) / 2
    }

    /// 1 when the coffee table is centered in front of the sofa, 45 cm
    /// away and turned the same way; less the further off it is.
    static func coffeeTableFit(_ table: PlacedItem, sofa: PlacedItem) -> Double {
        let ideal = offset(sofa.center, sofa.front, sofa.item.depth / 2 + 45 + table.item.depth / 2)
        let closeness = max(0, 1 - max(0, table.center.distance(to: ideal) - 10) / 60)
        let turned = table.placement.rotation % 180 == sofa.placement.rotation % 180 ? 1.0 : 0.5
        return closeness * turned
    }

    /// 1 when an armchair is near the middle of the seating group and
    /// facing it.
    static func conversationFit(_ chair: PlacedItem, hub: Point2D) -> Double {
        let distance = chair.center.distance(to: hub)
        let closeness = max(0, 1 - max(0, distance - 180) / 100)
        return closeness * (0.2 + 0.8 * facing(chair, toward: hub))
    }

    /// 1 when a lamp stands right beside a seat, bed, or desk.
    static func lampFit(_ lamp: PlacedItem, among placed: [PlacedItem]) -> Double {
        let anchors = placed.filter { [.sofa, .chair, .bed, .desk].contains($0.item.type) }
        let gap = anchors.map { gap(between: lamp.footprint, and: $0.footprint) }.min() ?? 1_000
        return max(0, 1 - max(0, gap - 15) / 85)
    }

    /// The middle of the seating group: the coffee table, or where it
    /// would go in front of the sofa.
    static func groupHub(sofa: PlacedItem, placed: [PlacedItem]) -> Point2D {
        if let table = placed.first(where: { $0.item.isCoffeeTable }) { return table.center }
        return offset(sofa.center, sofa.front, sofa.item.depth / 2 + 75)
    }

    static func mainSofa(_ placed: [PlacedItem]) -> PlacedItem? {
        placed.first { $0.item.type == .sofa }
    }

    /// Shortest distance between two boxes (zero when they touch).
    static func gap(between a: Box, and b: Box) -> Double {
        let dx = max(a.minX - b.maxX, 0, b.minX - a.maxX)
        let dy = max(a.minY - b.maxY, 0, b.minY - a.maxY)
        return hypot(dx, dy)
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
        // ...and that keep the seating group about as well together as
        // the best one does, so "Most open floor" never means scattered.
        let fewestLeftOut = sorted.map(\.leftOut.count).min() ?? 0
        let complete = sorted.filter { $0.leftOut.count == fewestLeftOut }
        let bestGrouping = complete.map(\.breakdown.grouping).max() ?? 0
        take(from: complete.filter { $0.breakdown.grouping >= bestGrouping - 0.2 }, upTo: count)
        // ...then, if that gives fewer than 3, top up with the rest.
        take(from: complete, upTo: max(min(3, count), picked.count))
        take(from: sorted, upTo: max(min(3, count), picked.count))
        return picked
    }

    /// Makes sure the current layout is offered: it takes the place of a
    /// near copy of itself, or of the last option.
    private static func keep(_ current: LayoutSuggestion, in picked: inout [LayoutSuggestion], count: Int) {
        guard !picked.contains(where: { $0.placements == current.placements }) else { return }
        if let twin = picked.firstIndex(where: { difference($0, current) < 40 }) {
            picked[twin] = current
        } else if picked.count < count {
            picked.append(current)
        } else if !picked.isEmpty {
            picked[picked.count - 1] = current
        }
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

    /// A direction a quarter turn from `direction`.
    private static func sideways(_ direction: Point2D) -> Point2D {
        Point2D(x: -direction.y, y: direction.x)
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
