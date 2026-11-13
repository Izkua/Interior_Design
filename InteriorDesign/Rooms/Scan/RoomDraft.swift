import Foundation
import SwiftData

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
    /// Furniture a LiDAR scan found, ready to add to the room. Other scans
    /// leave this empty.
    var furniture: [ScannedFurniture] = []

    /// Walls below this confidence get highlighted for the person to check.
    static let confidentEnough = 0.6

    /// The same draft with no furniture: just walls, doors and windows.
    var withoutFurniture: RoomDraft {
        var copy = self
        copy.furniture = []
        return copy
    }

    /// Walls nobody saw clearly.
    var uncertainWalls: [Int] {
        walls.indices.filter { !walls[$0].seen || walls[$0].confidence < Self.confidentEnough }
    }

    /// The scan is done when the outline is closed and every wall was seen.
    var isComplete: Bool {
        closed && walls.allSatisfy(\.seen)
    }
}

/// A piece of furniture a LiDAR (RoomPlan) scan found, in the draft's
/// centimeters. Its size is a box around the piece, so it's an estimate.
struct ScannedFurniture: Equatable, Sendable {
    var type: ItemType
    var widthCm: Double
    var depthCm: Double
    var heightCm: Double
    /// Center on the floor plan.
    var x: Double
    var y: Double
    /// 0, 90, 180, or 270 degrees, like `ItemPlacement`.
    var rotation: Int

    /// The floor it covers: turned 90° or 270°, width and depth swap.
    var footprint: (width: Double, depth: Double) {
        rotation % 180 == 0 ? (widthCm, depthCm) : (depthCm, widthCm)
    }

    /// The pieces nudged toward the room's middle (up to 40 cm) until
    /// their footprint is inside the walls. A scanned box often reaches a
    /// few centimeters into the wall it stands against.
    static func keptInside(_ pieces: [ScannedFurniture], corners: [Point2D]) -> [ScannedFurniture] {
        guard corners.count >= 3 else { return pieces }
        let middle = PolygonGeometry.centroid(corners)
        return pieces.map { piece in
            let distance = hypot(middle.x - piece.x, middle.y - piece.y)
            guard distance > 0.5 else { return piece }
            let step = (x: (middle.x - piece.x) / distance, y: (middle.y - piece.y) / distance)
            for cm in stride(from: 0.0, through: min(40, distance), by: 1) {
                var moved = piece
                moved.x += step.x * cm
                moved.y += step.y * cm
                if moved.isInside(corners) { return moved }
            }
            return piece
        }
    }

    /// True when all four corners of the footprint are inside the outline.
    func isInside(_ corners: [Point2D]) -> Bool {
        let (w, d) = footprint
        let box = [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].map { Point2D(x: x + $0.0 * w / 2, y: y + $0.1 * d / 2) }
        return box.allSatisfy { Self.point($0, isInside: corners) }
    }

    /// Even-odd ray test; points on a wall count as inside.
    private static func point(_ p: Point2D, isInside corners: [Point2D]) -> Bool {
        var inside = false
        var j = corners.count - 1
        for i in corners.indices {
            let a = corners[i], b = corners[j]
            // On this wall (within half a centimeter)?
            let length = hypot(b.x - a.x, b.y - a.y)
            if length > 0 {
                let t = ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / (length * length)
                if t >= 0, t <= 1, hypot(a.x + t * (b.x - a.x) - p.x, a.y + t * (b.y - a.y) - p.y) < 0.5 { return true }
            }
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// "1 bed, 2 chairs and a table" style summary for the review screen.
    static func summary(_ pieces: [ScannedFurniture]) -> String {
        var counts: [(ItemType, Int)] = []
        for piece in pieces {
            if let i = counts.firstIndex(where: { $0.0 == piece.type }) { counts[i].1 += 1 } else { counts.append((piece.type, 1)) }
        }
        let parts = counts.map { type, count in
            let name = type.displayName.lowercased()
            return count == 1 ? "1 \(name)" : "\(count) \(name == "shelf" ? "shelve" : name)s"
        }
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
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

    /// Adds furniture from a LiDAR scan as new items in this room, placed
    /// where the scan saw them. Sizes stay "estimated" until the person
    /// checks them. Returns the new items.
    @discardableResult
    func addScannedFurniture(_ pieces: [ScannedFurniture], context: ModelContext) -> [Item] {
        guard !pieces.isEmpty else { return [] }
        let current = chosenLayout
        var placements = current?.placements ?? []
        var added: [Item] = []
        for piece in pieces {
            let item = Item(type: piece.type, widthCm: piece.widthCm, depthCm: piece.depthCm,
                            heightCm: piece.heightCm, isEstimated: true)
            context.insert(item)
            item.setRooms([self], anyRoom: false)
            placements.append(ItemPlacement(itemID: item.uuid, x: piece.x, y: piece.y, rotation: piece.rotation))
            added.append(item)
        }
        choose(placements, label: current?.label ?? "Current arrangement", score: current?.score ?? 0, context: context)
        return added
    }
}
