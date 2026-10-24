import Foundation

/// Math for rooms of any shape, used by the advanced room builder.
///
/// Corners use the same coordinates as `PlanGeometry`: centimeters, x to
/// the right, y downward, listed clockwise as seen on screen, and wall `i`
/// runs from corner `i` to corner `i + 1`. Because y points down, a room
/// listed clockwise on screen has a *positive* signed area below.
enum PolygonGeometry {
    // MARK: Lengths and area

    /// Length of the wall between two corners.
    static func wallLength(from a: Point2D, to b: Point2D) -> Double {
        PlanGeometry.distance(a, b)
    }

    /// Area with a sign that shows the winding order (the shoelace
    /// formula). Positive means clockwise on screen.
    static func signedArea(_ corners: [Point2D]) -> Double {
        let count = corners.count
        guard count >= 3 else { return 0 }
        var sum = 0.0
        for i in 0..<count {
            let a = corners[i]
            let b = corners[(i + 1) % count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    /// Floor area in square centimeters.
    static func area(_ corners: [Point2D]) -> Double {
        abs(signedArea(corners))
    }

    /// True when the corners go clockwise on screen, the order the rest of
    /// the app expects.
    static func isClockwise(_ corners: [Point2D]) -> Bool {
        signedArea(corners) > 0
    }

    /// The same corners, reversed if needed so they run clockwise on
    /// screen. Corner 0 stays first.
    static func clockwise(_ corners: [Point2D]) -> [Point2D] {
        guard corners.count >= 3, !isClockwise(corners) else { return corners }
        return [corners[0]] + corners.dropFirst().reversed()
    }

    // MARK: Angles

    /// The angle inside the room at a corner, in degrees from 0 to 360.
    /// A normal corner is 90; the inner corner of an L-shaped room is 270.
    static func interiorAngle(at index: Int, corners: [Point2D]) -> Double {
        let count = corners.count
        guard count >= 3 else { return 0 }
        let i = wrap(index, count)
        let corner = corners[i]
        let previous = corners[wrap(i - 1, count)]
        let next = corners[wrap(i + 1, count)]

        // Turn from the wall going out to the wall coming in. Which way
        // counts as "inside" depends on the winding order.
        let toNext = atan2(next.y - corner.y, next.x - corner.x)
        let toPrevious = atan2(previous.y - corner.y, previous.x - corner.x)
        let turn = degrees(toPrevious - toNext)
        return isClockwise(corners) ? normalized(turn) : normalized(-turn)
    }

    /// Angles a corner can snap to when "Lock angles" is on, including the
    /// inside-out (reflex) versions used by L-shaped rooms.
    static let snapAngles: [Double] = {
        let common: [Double] = [30, 45, 60, 90, 120, 135, 150, 180]
        let reflex = common.dropLast().map { 360 - $0 }
        return (common + reflex).sorted()
    }()

    /// The allowed angle closest to `angle`.
    static func snappedAngle(_ angle: Double) -> Double {
        let target = normalized(angle)
        return snapAngles.min { abs($0 - target) < abs($1 - target) } ?? target
    }

    /// Where a dragged corner should land with "Lock angles" on.
    ///
    /// The walls on both sides of the corner are turned so the angles at
    /// the neighboring corners snap, and the corner goes where those two
    /// walls meet. That makes a near-square corner exactly square. If the
    /// two walls do not meet near the finger, only the wall before the
    /// corner is snapped.
    static func snapCorner(_ index: Int, to point: Point2D, corners: [Point2D]) -> Point2D {
        let count = corners.count
        guard count >= 3 else { return point }
        let i = wrap(index, count)
        var moved = corners
        moved[i] = point
        let sign: Double = isClockwise(moved) ? 1 : -1

        // The wall arriving from the previous corner.
        let prevIndex = wrap(i - 1, count)
        let prev = corners[prevIndex]
        let beforePrev = corners[wrap(i - 2, count)]
        let prevAngle = snappedAngle(interiorAngle(at: prevIndex, corners: moved))
        let fromPrev = atan2(beforePrev.y - prev.y, beforePrev.x - prev.x) - sign * radians(prevAngle)

        // The wall leaving toward the next corner, seen from that corner.
        let nextIndex = wrap(i + 1, count)
        let next = corners[nextIndex]
        let afterNext = corners[wrap(i + 2, count)]
        let nextAngle = snappedAngle(interiorAngle(at: nextIndex, corners: moved))
        let fromNext = atan2(afterNext.y - next.y, afterNext.x - next.x) + sign * radians(nextAngle)

        let reach = PlanGeometry.distance(prev, point)
        if count > 3,
           let meet = rayIntersection(from: prev, angle: fromPrev, and: next, angle: fromNext),
           PlanGeometry.distance(meet, point) <= max(30, reach * 0.25) {
            return meet
        }

        // Keep the finger's distance from the previous corner, along the
        // snapped direction.
        return Point2D(x: prev.x + cos(fromPrev) * reach, y: prev.y + sin(fromPrev) * reach)
    }

    // MARK: Shape checks

    /// True when the outline is a real room: at least three corners, no
    /// zero-length walls, and no walls crossing each other.
    static func isSimple(_ corners: [Point2D]) -> Bool {
        let count = corners.count
        guard count >= 3 else { return false }
        for i in 0..<count where wallLength(from: corners[i], to: corners[(i + 1) % count]) < 0.5 {
            return false
        }
        for i in 0..<count {
            for j in (i + 1)..<count {
                // Walls that share a corner always touch; skip them.
                let adjacent = j == i + 1 || (i == 0 && j == count - 1)
                if adjacent { continue }
                if segmentsIntersect(
                    corners[i], corners[(i + 1) % count],
                    corners[j], corners[(j + 1) % count]
                ) {
                    return false
                }
            }
        }
        return true
    }

    /// True when segment a–b touches or crosses segment c–d.
    static func segmentsIntersect(_ a: Point2D, _ b: Point2D, _ c: Point2D, _ d: Point2D) -> Bool {
        let d1 = cross(c, d, a)
        let d2 = cross(c, d, b)
        let d3 = cross(a, b, c)
        let d4 = cross(a, b, d)
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }
        // Touching or overlapping in a line.
        return (d1 == 0 && onSegment(c, d, a))
            || (d2 == 0 && onSegment(c, d, b))
            || (d3 == 0 && onSegment(a, b, c))
            || (d4 == 0 && onSegment(a, b, d))
    }

    // MARK: Measured walls

    /// The corners after giving one wall a new length. The wall keeps its
    /// direction and its far corner moves; every other corner stays put.
    static func settingWallLength(_ wall: Int, to length: Double, corners: [Point2D]) -> [Point2D] {
        let count = corners.count
        guard count >= 2, length > 0 else { return corners }
        let i = wrap(wall, count)
        let a = corners[i]
        let b = corners[wrap(i + 1, count)]
        let current = PlanGeometry.distance(a, b)
        guard current > 0 else { return corners }
        var result = corners
        result[wrap(i + 1, count)] = Point2D(
            x: a.x + (b.x - a.x) / current * length,
            y: a.y + (b.y - a.y) / current * length
        )
        return result
    }

    /// What goes wrong when walking around the room with the measured wall
    /// lengths: the walk ends `gap` centimeters from where it started.
    struct ClosureCheck: Equatable {
        /// How far the walk misses its starting corner, in cm.
        var gap: Double
        /// The wall that best explains the miss: changing its length
        /// closes most of the gap.
        var wall: Int
        /// The length that wall would need, in cm.
        var suggestedLength: Double
        /// `suggestedLength` minus the measured length. Positive means the
        /// wall needs to be longer.
        var difference: Double
    }

    /// Walks the room wall by wall, using each wall's drawn direction and
    /// the given lengths. Returns nil when the walk comes back to the
    /// start (within `tolerance` cm), which means the lengths agree.
    static func closureCheck(corners: [Point2D], lengths: [Double], tolerance: Double = 2) -> ClosureCheck? {
        let count = corners.count
        guard count >= 3, lengths.count == count else { return nil }
        let directions = wallDirections(corners)

        var gapX = 0.0
        var gapY = 0.0
        for i in 0..<count {
            gapX += directions[i].x * lengths[i]
            gapY += directions[i].y * lengths[i]
        }
        let gap = hypot(gapX, gapY)
        guard gap > tolerance else { return nil }

        // The wall pointing most along the gap; shortening it by the gap's
        // share along its direction closes the most.
        var best = 0
        var bestShare = 0.0
        for i in 0..<count {
            let share = directions[i].x * gapX + directions[i].y * gapY
            if abs(share) > abs(bestShare) + 0.001 {
                best = i
                bestShare = share
            }
        }
        let suggested = max(lengths[best] - bestShare, 1)
        return ClosureCheck(
            gap: gap,
            wall: best,
            suggestedLength: suggested,
            difference: suggested - lengths[best]
        )
    }

    /// Rebuilds the outline from wall lengths, keeping each wall's drawn
    /// direction, then spreads any leftover gap across the corners so the
    /// outline closes. (Surveyors call this the compass rule: each corner
    /// moves in proportion to how far along the walk it is.)
    static func closedOutline(corners: [Point2D], lengths: [Double]) -> [Point2D] {
        let count = corners.count
        guard count >= 3, lengths.count == count else { return corners }
        let directions = wallDirections(corners)
        let perimeter = lengths.reduce(0, +)
        guard perimeter > 0 else { return corners }

        // Walk the walls, remembering where each corner lands.
        var walked = [corners[0]]
        for i in 0..<count {
            let last = walked[walked.count - 1]
            walked.append(Point2D(
                x: last.x + directions[i].x * lengths[i],
                y: last.y + directions[i].y * lengths[i]
            ))
        }
        let gapX = walked[count].x - walked[0].x
        let gapY = walked[count].y - walked[0].y

        var result: [Point2D] = []
        var travelled = 0.0
        for i in 0..<count {
            let share = travelled / perimeter
            result.append(Point2D(x: walked[i].x - gapX * share, y: walked[i].y - gapY * share))
            travelled += lengths[i]
        }
        return result
    }

    // MARK: Helpers

    /// Unit vector along each wall.
    private static func wallDirections(_ corners: [Point2D]) -> [Point2D] {
        let count = corners.count
        return (0..<count).map { i in
            let a = corners[i]
            let b = corners[(i + 1) % count]
            let length = PlanGeometry.distance(a, b)
            guard length > 0 else { return .zero }
            return Point2D(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
        }
    }

    /// Where two rays meet, or nil if they are parallel or meet behind
    /// either start point.
    private static func rayIntersection(from a: Point2D, angle angleA: Double, and b: Point2D, angle angleB: Double) -> Point2D? {
        let ux = cos(angleA), uy = sin(angleA)
        let vx = cos(angleB), vy = sin(angleB)
        let denominator = ux * vy - uy * vx
        guard abs(denominator) > 1e-9 else { return nil }
        let dx = b.x - a.x
        let dy = b.y - a.y
        let s = (dx * vy - dy * vx) / denominator
        let t = (dx * uy - dy * ux) / denominator
        guard s > 0, t > 0 else { return nil }
        return Point2D(x: a.x + ux * s, y: a.y + uy * s)
    }

    /// Positive when `p` is on one side of the line a–b, negative on the
    /// other, zero on it.
    private static func cross(_ a: Point2D, _ b: Point2D, _ p: Point2D) -> Double {
        let value = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
        return abs(value) < 1e-9 ? 0 : value
    }

    /// For a point already on the line a–b: is it between a and b?
    private static func onSegment(_ a: Point2D, _ b: Point2D, _ p: Point2D) -> Bool {
        p.x >= min(a.x, b.x) - 1e-9 && p.x <= max(a.x, b.x) + 1e-9
            && p.y >= min(a.y, b.y) - 1e-9 && p.y <= max(a.y, b.y) + 1e-9
    }

    static func wrap(_ index: Int, _ count: Int) -> Int {
        ((index % count) + count) % count
    }

    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    /// An angle moved into 0..<360.
    private static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}
