import SwiftUI
import RoomPlan
import simd

/// Room scanning with Apple's RoomPlan, on iPhones with LiDAR (Pro models).
/// It measures walls, doors, and windows directly, so it's much more
/// accurate than photos. Hidden everywhere else, including the Simulator.
enum RoomPlanScan {
    static var isAvailable: Bool { RoomCaptureSession.isSupported }
}

/// One wall seen from above, in meters, as RoomPlan reports it.
struct WallSegment: Equatable {
    var centerX: Double
    var centerZ: Double
    var length: Double
    /// Direction the wall runs, in radians, measured in the floor plane.
    var angle: Double

    var start: Point2D {
        Point2D(x: centerX - cos(angle) * length / 2, y: centerZ - sin(angle) * length / 2)
    }
    var end: Point2D {
        Point2D(x: centerX + cos(angle) * length / 2, y: centerZ + sin(angle) * length / 2)
    }
}

/// A door or window from RoomPlan, in meters.
struct OpeningSegment: Equatable {
    var kind: FeatureKind
    var centerX: Double
    var centerZ: Double
    var width: Double
}

/// A piece of furniture from RoomPlan, in meters. Its box's own x axis
/// runs along the width, at `angle` in the floor plane.
struct ObjectBox: Equatable {
    var type: ItemType
    var centerX: Double
    var centerZ: Double
    var width: Double
    var depth: Double
    var height: Double
    var angle: Double
}

/// Turns RoomPlan's walls into our outline. Pure math, so it's tested
/// without a LiDAR phone.
enum RoomPlanConverter {
    static func draft(walls: [WallSegment], openings: [OpeningSegment], objects: [ObjectBox] = []) -> RoomDraft? {
        guard walls.count >= 3 else { return nil }
        // Walk around the room: sort walls by their direction from the middle.
        let midX = walls.map(\.centerX).reduce(0, +) / Double(walls.count)
        let midZ = walls.map(\.centerZ).reduce(0, +) / Double(walls.count)
        let ordered = walls.sorted {
            atan2($0.centerZ - midZ, $0.centerX - midX) < atan2($1.centerZ - midZ, $1.centerX - midX)
        }
        // Each corner is where two neighboring walls meet.
        var corners: [Point2D] = []
        for i in ordered.indices {
            let a = ordered[i], b = ordered[(i + 1) % ordered.count]
            let point = intersection(a, b) ?? Point2D(x: (a.end.x + b.start.x) / 2, y: (a.end.y + b.start.y) / 2)
            corners.append(Point2D(x: point.x * 100, y: point.y * 100))  // meters → cm
        }
        // Corner i is the end of wall i, so rotate by one to make wall i run
        // from corner i to corner i + 1.
        corners = [corners[corners.count - 1]] + corners.dropLast()

        var features: [[String: Any]] = []
        for opening in openings {
            let spot = Point2D(x: opening.centerX * 100, y: opening.centerZ * 100)
            let hit = PlanGeometry.nearestWall(to: spot, corners: corners)
            features.append(["kind": opening.kind.rawValue, "wall": hit.wall, "offsetCm": hit.offset, "widthCm": opening.width * 100])
        }
        let json: [String: Any] = [
            "corners": corners.map { ["x": $0.x, "y": $0.y] },
            "walls": corners.map { _ in ["seen": true, "confidence": 0.9] },
            "features": features,
            "closed": true,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        // The parser fixes the order, the origin, and checks for crossings.
        guard var draft = try? RoomDraftParser.parse(data) else { return nil }
        // The parser moved the outline so its top-left is 0,0 (and may have
        // reversed the corner order, which doesn't move anything), so move
        // the furniture the same way.
        let shift = Point2D(x: corners.map(\.x).min()!, y: corners.map(\.y).min()!)
        draft.furniture = furniture(objects, shift: shift, corners: draft.corners)
        return draft
    }

    /// RoomPlan's furniture boxes as pieces on our plan. Each turn is
    /// rounded to the nearest quarter turn, and of the two ways a piece
    /// could face, we pick the one facing into the room (beds and sofas
    /// usually back onto a wall).
    static func furniture(_ objects: [ObjectBox], shift: Point2D, corners: [Point2D]) -> [ScannedFurniture] {
        let middle = PolygonGeometry.centroid(corners)
        return objects.compactMap { box in
            guard [box.centerX, box.centerZ, box.width, box.depth, box.height, box.angle].allSatisfy(\.isFinite),
                  box.width > 0.05, box.depth > 0.05 else { return nil }
            let x = box.centerX * 100 - shift.x
            let y = box.centerZ * 100 - shift.y
            let quarter = Int((box.angle / (.pi / 2)).rounded())
            let sideways = ((quarter % 2) + 2) % 2 == 1
            let choices = sideways ? [90, 270] : [0, 180]
            let toMiddle = Point2D(x: middle.x - x, y: middle.y - y)
            func facing(_ rotation: Int) -> Double {
                let front = Facing.front(rotation)
                return front.x * toMiddle.x + front.y * toMiddle.y
            }
            let rotation = facing(choices[0]) >= facing(choices[1]) ? choices[0] : choices[1]
            return ScannedFurniture(type: box.type, widthCm: box.width * 100, depthCm: box.depth * 100,
                                    heightCm: max(box.height * 100, 1), x: x, y: y, rotation: rotation)
        }
    }

    /// Where the two walls' lines cross, or nil if they're parallel.
    private static func intersection(_ a: WallSegment, _ b: WallSegment) -> Point2D? {
        let (ax, az, bx, bz) = (cos(a.angle), sin(a.angle), cos(b.angle), sin(b.angle))
        let denominator = ax * bz - az * bx
        guard abs(denominator) > 1e-6 else { return nil }
        let t = ((b.centerX - a.centerX) * bz - (b.centerZ - a.centerZ) * bx) / denominator
        return Point2D(x: a.centerX + ax * t, y: a.centerZ + az * t)
    }
}

/// The RoomPlan scanning screen. Calls back with a draft when finished.
struct RoomPlanScanView: UIViewRepresentable {
    let onFinish: (RoomDraft?) -> Void

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: RoomCaptureView, context: Context) {}

    static func dismantleUIView(_ view: RoomCaptureView, coordinator: RoomPlanCoordinator) {
        view.captureSession.stop()
    }

    func makeCoordinator() -> RoomPlanCoordinator { RoomPlanCoordinator(onFinish: onFinish) }
}

/// Receives RoomPlan's result. (RoomPlan requires its delegate to be a
/// top-level class that supports NSCoding.)
final class RoomPlanCoordinator: NSObject, RoomCaptureViewDelegate, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    let onFinish: (RoomDraft?) -> Void
    weak var view: RoomCaptureView?

    init(onFinish: @escaping (RoomDraft?) -> Void) { self.onFinish = onFinish }
    required init?(coder: NSCoder) { nil }
    func encode(with coder: NSCoder) {}

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool { true }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        onFinish(Self.draft(from: processedResult))
    }

    /// RoomPlan's 3D result, flattened to a floor plan.
    static func draft(from room: CapturedRoom) -> RoomDraft? {
        func floorPosition(_ t: simd_float4x4) -> (Double, Double) { (Double(t.columns.3.x), Double(t.columns.3.z)) }
        let walls = room.walls.map { wall -> WallSegment in
            let (x, z) = floorPosition(wall.transform)
            // The wall's own x axis runs along it.
            let axis = wall.transform.columns.0
            return WallSegment(centerX: x, centerZ: z, length: Double(wall.dimensions.x), angle: atan2(Double(axis.z), Double(axis.x)))
        }
        let openings = room.doors.map { ($0, FeatureKind.door) } + room.windows.map { ($0, FeatureKind.window) }
        let segments = openings.map { surface, kind -> OpeningSegment in
            let (x, z) = floorPosition(surface.transform)
            return OpeningSegment(kind: kind, centerX: x, centerZ: z, width: Double(surface.dimensions.x))
        }
        let objects = room.objects.compactMap { object -> ObjectBox? in
            guard let type = itemType(object.category, heightMeters: Double(object.dimensions.y)) else { return nil }
            let (x, z) = floorPosition(object.transform)
            let axis = object.transform.columns.0
            return ObjectBox(type: type, centerX: x, centerZ: z,
                             width: Double(object.dimensions.x), depth: Double(object.dimensions.z),
                             height: Double(object.dimensions.y), angle: atan2(Double(axis.z), Double(axis.x)))
        }
        return RoomPlanConverter.draft(walls: walls, openings: segments, objects: objects)
    }

    /// Our item type for what RoomPlan saw. Kitchen and bathroom fixtures
    /// (fridge, oven, toilet, bathtub...) and TVs aren't furniture you
    /// arrange, so they're skipped.
    static func itemType(_ category: CapturedRoom.Object.Category, heightMeters: Double) -> ItemType? {
        switch category {
        case .bed: return .bed
        case .sofa: return .sofa
        case .chair: return .chair
        case .table: return .table
        // Tall storage is a bookcase or wardrobe; low storage a dresser.
        case .storage: return heightMeters > 1.2 ? .shelf : .dresser
        default: return nil
        }
    }
}
