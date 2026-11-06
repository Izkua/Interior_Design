import Foundation

/// Turns slightly-off scanned walls into regular angles. Pure math, so it's
/// unit-tested and shared by AR tracing (as you aim) and the scan review
/// ("Straighten corners").
///
/// Angles are measured against the first wall. A wall within `tolerance`
/// of a right angle (0°, 90°, 180°, 270°) snaps to it; otherwise, if
/// 45° turns are allowed, one within `tolerance` of a 45° line snaps to
/// that; anything else is left as traced (a genuinely odd wall).
enum RoomStraightener {
    static let tolerance = 15.0 * .pi / 180

    /// Snaps one wall direction (radians) against the first wall's.
    /// Returns the new direction and whether it snapped.
    static func snap(_ angle: Double, base: Double, allow45: Bool = true) -> (angle: Double, snapped: Bool) {
        for step in allow45 ? [Double.pi / 2, .pi / 4] : [.pi / 2] {
            let turns = ((angle - base) / step).rounded()
            let target = base + turns * step
            if abs(remainder(angle - target, 2 * .pi)) <= tolerance { return (target, true) }
        }
        return (angle, false)
    }

    /// The turn from one wall to the next, in whole degrees (0 to 180),
    /// for the "90°" badge.
    static func turnDegrees(from a: Double, to b: Double) -> Int {
        Int((abs(remainder(b - a, 2 * .pi)) * 180 / .pi).rounded())
    }

    /// The straightened outline, or nil when nothing needs changing (or it
    /// can't be done without breaking the shape).
    ///
    /// Each wall's direction is snapped, then its length is nudged as
    /// little as possible (least squares, longer walls take more of the
    /// nudge) so the outline closes exactly. A noisy rectangle comes out
    /// as a rectangle with matching opposite walls.
    static func straightened(_ corners: [Point2D], allow45: Bool = true) -> [Point2D]? {
        let n = corners.count
        guard n >= 3 else { return nil }
        var lengths: [Double] = [], angles: [Double] = []
        for i in 0..<n {
            let a = corners[i], b = corners[(i + 1) % n]
            lengths.append(hypot(b.x - a.x, b.y - a.y))
            angles.append(atan2(b.y - a.y, b.x - a.x))
        }
        guard lengths.allSatisfy({ $0 > 1 }) else { return nil }
        let base = angles[0]
        let directions = angles.map { snap($0, base: base, allow45: allow45).angle }

        // Close the loop: minimise Σ (l − L)² / L subject to Σ l·d = 0.
        // With Lagrange multipliers: l = L − L (d · λ), where M λ = gap,
        // M = Σ L d dᵀ and gap = Σ L d.
        var m00 = 0.0, m01 = 0.0, m11 = 0.0, gx = 0.0, gy = 0.0
        for i in 0..<n {
            let dx = cos(directions[i]), dy = sin(directions[i]), w = lengths[i]
            m00 += w * dx * dx; m01 += w * dx * dy; m11 += w * dy * dy
            gx += w * dx; gy += w * dy
        }
        let det = m00 * m11 - m01 * m01
        guard abs(det) > 1e-6 else { return nil }
        let lx = (m11 * gx - m01 * gy) / det, ly = (m00 * gy - m01 * gx) / det
        let fitted = (0..<n).map { i in
            lengths[i] - lengths[i] * (cos(directions[i]) * lx + sin(directions[i]) * ly)
        }
        // Don't let a wall shrink to nothing or change too much (> 25 %).
        for i in 0..<n where fitted[i] < 5 || abs(fitted[i] - lengths[i]) > max(0.25 * lengths[i], 15) {
            return nil
        }

        var result = [corners[0]]
        for i in 0..<(n - 1) {
            let p = result[i]
            result.append(Point2D(x: p.x + cos(directions[i]) * fitted[i], y: p.y + sin(directions[i]) * fitted[i]))
        }
        guard PolygonGeometry.isSimple(result) else { return nil }
        // Nothing worth changing (every corner within half a centimetre).
        let moved = zip(result, corners).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
        return moved < 0.5 ? nil : result
    }

    /// The same for a whole scan draft: doors and windows keep their place
    /// along their wall (in proportion), and the outline is moved back so
    /// its top-left corner is at 0,0.
    static func straightened(_ draft: RoomDraft, allow45: Bool = true) -> RoomDraft? {
        guard let corners = straightened(draft.corners, allow45: allow45) else { return nil }
        let minX = corners.map(\.x).min() ?? 0, minY = corners.map(\.y).min() ?? 0
        var result = draft
        result.corners = corners.map { Point2D(x: $0.x - minX, y: $0.y - minY) }
        result.features = draft.features.map { f in
            var moved = f
            let old = PlanGeometry.wallLength(f.wall, corners: draft.corners)
            let new = PlanGeometry.wallLength(f.wall, corners: result.corners)
            if old > 0 { moved.offsetCm = f.offsetCm * new / old }
            return moved
        }
        return result
    }
}
