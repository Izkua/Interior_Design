import Foundation

/// A point on the floor plan, in centimeters. The origin is the top-left
/// corner; x grows to the right and y grows downward.
struct Point2D: Codable, Hashable {
    var x: Double
    var y: Double

    static let zero = Point2D(x: 0, y: 0)
}

/// Math for rooms made of straight walls. Corners are listed clockwise
/// (as seen on screen), and wall `i` runs from corner `i` to corner `i + 1`.
enum PlanGeometry {
    static func distance(_ a: Point2D, _ b: Point2D) -> Double {
        hypot(b.x - a.x, b.y - a.y)
    }

    /// Corners of a rectangle, clockwise from the top-left.
    static func rectangleCorners(width: Double, length: Double) -> [Point2D] {
        [
            Point2D(x: 0, y: 0),
            Point2D(x: width, y: 0),
            Point2D(x: width, y: length),
            Point2D(x: 0, y: length)
        ]
    }

    static func wallLength(_ wall: Int, corners: [Point2D]) -> Double {
        let count = corners.count
        guard count >= 2 else { return 0 }
        let index = ((wall % count) + count) % count
        return distance(corners[index], corners[(index + 1) % count])
    }

    /// The point `offset` centimeters along a wall, measured from the wall's
    /// first corner.
    static func point(onWall wall: Int, offset: Double, corners: [Point2D]) -> Point2D {
        let count = corners.count
        guard count >= 2 else { return .zero }
        let index = ((wall % count) + count) % count
        let a = corners[index]
        let b = corners[(index + 1) % count]
        let length = distance(a, b)
        guard length > 0 else { return a }
        let t = offset / length
        return Point2D(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// The wall closest to `p`, and how far along that wall the closest
    /// point is.
    static func nearestWall(to p: Point2D, corners: [Point2D]) -> (wall: Int, offset: Double) {
        let count = corners.count
        guard count >= 2 else { return (0, 0) }

        var bestWall = 0
        var bestOffset = 0.0
        var bestDistance = Double.infinity

        for i in 0..<count {
            let a = corners[i]
            let b = corners[(i + 1) % count]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0 else { continue }

            let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
            let closest = Point2D(x: a.x + t * dx, y: a.y + t * dy)
            let d = distance(p, closest)
            if d < bestDistance {
                bestDistance = d
                bestWall = i
                bestOffset = t * lengthSquared.squareRoot()
            }
        }
        return (bestWall, bestOffset)
    }

    /// Keeps something of the given width fully inside a wall.
    static func clampOffset(_ offset: Double, width: Double, wallLength: Double) -> Double {
        let half = min(width / 2, wallLength / 2)
        return min(max(offset, half), wallLength - half)
    }

    /// The emptiest stretch of wall for something new of the given width,
    /// so a new door does not land on top of a window. Walls are tried in
    /// `preferredWalls` order first; the first wall with a big enough gap
    /// wins, and the spot is the middle of that wall's widest gap. If no
    /// wall has room, the widest gap anywhere is used.
    static func freeSpot(
        width: Double,
        preferredWalls: [Int],
        corners: [Point2D],
        taken: [(wall: Int, offset: Double, width: Double)]
    ) -> (wall: Int, offset: Double) {
        let count = corners.count
        guard count >= 2 else { return (0, 0) }

        var order = preferredWalls.filter { (0..<count).contains($0) }
        for wall in 0..<count where !order.contains(wall) {
            order.append(wall)
        }

        var widestAnywhere: (wall: Int, start: Double, end: Double)?
        for wall in order {
            let length = wallLength(wall, corners: corners)
            guard let gap = widestGap(onWallOfLength: length, spans: taken.filter { $0.wall == wall }) else {
                continue
            }
            if gap.end - gap.start >= width {
                return (wall, clampOffset((gap.start + gap.end) / 2, width: width, wallLength: length))
            }
            if widestAnywhere == nil || gap.end - gap.start > widestAnywhere!.end - widestAnywhere!.start {
                widestAnywhere = (wall, gap.start, gap.end)
            }
        }

        let fallback = widestAnywhere ?? (wall: order[0], start: 0.0, end: wallLength(order[0], corners: corners))
        return (
            fallback.wall,
            clampOffset(
                (fallback.start + fallback.end) / 2,
                width: width,
                wallLength: wallLength(fallback.wall, corners: corners)
            )
        )
    }

    /// The widest stretch of a wall not covered by any of `spans`.
    private static func widestGap(
        onWallOfLength length: Double,
        spans: [(wall: Int, offset: Double, width: Double)]
    ) -> (start: Double, end: Double)? {
        guard length > 0 else { return nil }
        let covered = spans
            .map { (start: max($0.offset - $0.width / 2, 0), end: min($0.offset + $0.width / 2, length)) }
            .sorted { $0.start < $1.start }

        var best: (start: Double, end: Double)?
        var cursor = 0.0
        func consider(_ start: Double, _ end: Double) {
            guard end > start else { return }
            if best == nil || end - start > best!.end - best!.start {
                best = (start, end)
            }
        }
        for span in covered {
            consider(cursor, span.start)
            cursor = max(cursor, span.end)
        }
        consider(cursor, length)
        return best
    }

    /// "Top wall", "Right wall", and so on for four-sided rooms.
    static func wallName(_ wall: Int, cornerCount: Int) -> String {
        if cornerCount == 4 {
            let names = ["Top", "Right", "Bottom", "Left"]
            return "\(names[((wall % 4) + 4) % 4]) wall"
        }
        return "Wall \(wall + 1)"
    }
}
