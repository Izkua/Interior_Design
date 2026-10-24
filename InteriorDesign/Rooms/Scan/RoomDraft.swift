import Foundation

/// A rough room outline from a scan, before the person checks it.
///
/// The JSON contract (what the scan-room function returns, version 1):
///
///     {
///       "version": 1,
///       "corners": [{"x": 0, "y": 0}, {"x": 420, "y": 0}, ...],   // cm, seen from above
///       "walls":   [{"seen": true, "confidence": 0.9}, ...],      // walls[i] runs corners[i] → corners[i+1]
///       "features": [{"kind": "door", "wall": 2, "offsetCm": 80, "widthCm": 90, "confidence": 0.7}],
///       "closed": true,                                          // the outline goes all the way round
///       "next": {"direction": "left", "hint": "Turn left to the wall with the window."}
///     }
///
/// Everything except `corners` is optional. The parser fixes what it can
/// (corner order, missing wall info) and rejects what it can't.
struct RoomDraft: Equatable, Sendable {
    struct Wall: Equatable, Sendable {
        var seen: Bool
        /// 0 to 1.
        var confidence: Double
    }

    /// Which way to point the camera next.
    enum Direction: String, Codable, Sendable {
        case left, right, behind, ahead, up, down, done
    }

    var corners: [Point2D]
    var walls: [Wall]
    var features: [FixedFeature]
    var closed: Bool
    var nextDirection: Direction?
    var nextHint: String?

    /// Walls below this confidence get highlighted for the person to check.
    static let confidentEnough = 0.6

    /// Walls nobody saw clearly.
    var uncertainWalls: [Int] {
        walls.indices.filter { !walls[$0].seen || walls[$0].confidence < Self.confidentEnough }
    }

    /// The scan is done when the outline is closed and every wall was seen.
    var isComplete: Bool {
        closed && walls.allSatisfy(\.seen)
    }
}

enum RoomDraftError: Error, Equatable {
    case notJSON
    case tooFewCorners
    case badNumbers
    case crossingWalls
}

enum RoomDraftParser {
    /// Biggest believable room side, in cm (50 m).
    static let maxSize = 5_000.0

    private struct Raw: Decodable {
        struct Corner: Decodable { var x: Double; var y: Double }
        struct Wall: Decodable { var seen: Bool?; var confidence: Double? }
        struct Feature: Decodable {
            var kind: String
            var wall: Int
            var offsetCm: Double
            var widthCm: Double?
            var confidence: Double?
        }
        struct Next: Decodable { var direction: String?; var hint: String? }

        var corners: [Corner]
        var walls: [Wall]?
        var features: [Feature]?
        var closed: Bool?
        var next: Next?
    }

    static func parse(_ data: Data) throws -> RoomDraft {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { throw RoomDraftError.notJSON }

        var corners = raw.corners.map { Point2D(x: $0.x, y: $0.y) }
        guard corners.count >= 3 else { throw RoomDraftError.tooFewCorners }
        guard corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw RoomDraftError.badNumbers }

        // Move the outline so its top-left is at 0,0, and check its size.
        let minX = corners.map(\.x).min()!, minY = corners.map(\.y).min()!
        corners = corners.map { Point2D(x: $0.x - minX, y: $0.y - minY) }
        guard corners.allSatisfy({ $0.x <= maxSize && $0.y <= maxSize }) else { throw RoomDraftError.badNumbers }
        guard PolygonGeometry.isSimple(corners) else { throw RoomDraftError.crossingWalls }

        let count = corners.count
        // One entry per wall; missing ones count as not seen.
        var walls = (0..<count).map { i -> RoomDraft.Wall in
            guard let w = raw.walls, i < w.count else { return .init(seen: false, confidence: 0) }
            let confidence = min(max(w[i].confidence ?? 0.5, 0), 1)
            return .init(seen: w[i].seen ?? true, confidence: confidence.isFinite ? confidence : 0)
        }

        var features: [FixedFeature] = (raw.features ?? []).compactMap { f in
            guard let kind = FeatureKind(rawValue: f.kind), (0..<count).contains(f.wall),
                  f.offsetCm.isFinite, f.offsetCm >= 0 else { return nil }
            let width = f.widthCm.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? kind.defaultWidthCm
            return FixedFeature(kind: kind, wall: f.wall, offsetCm: f.offsetCm, widthCm: width)
        }

        // The app wants corners clockwise on screen. If they came the other
        // way, reverse them; old wall k becomes wall n−1−k, running the
        // other direction, so offsets are measured from its other end.
        if !PolygonGeometry.isClockwise(corners) {
            let oldCorners = corners
            corners = [oldCorners[0]] + oldCorners.dropFirst().reversed()
            walls = (0..<count).map { walls[(count - 1 - $0)] }
            features = features.map { f in
                var flipped = f
                flipped.wall = count - 1 - f.wall
                flipped.offsetCm = PlanGeometry.wallLength(f.wall, corners: oldCorners) - f.offsetCm
                return flipped
            }
        }

        return RoomDraft(
            corners: corners,
            walls: walls,
            features: features,
            closed: raw.closed ?? true,
            nextDirection: raw.next?.direction.flatMap(RoomDraft.Direction.init(rawValue:)),
            nextHint: raw.next?.hint
        )
    }
}

extension Room {
    /// Replaces the outline with a scanned draft. The result is always an
    /// advanced (custom) room the person can edit, with unsure walls marked.
    func apply(_ draft: RoomDraft) {
        shape = .custom
        measurements = []
        outline = RoomOutline(corners: draft.corners, features: [], measurements: [])
        features = draft.features
        refitFeatures()
        uncertainWalls = draft.uncertainWalls
        updatedAt = Date()
    }
}
