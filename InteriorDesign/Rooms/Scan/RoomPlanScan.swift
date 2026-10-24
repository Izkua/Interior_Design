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

/// Turns RoomPlan's walls into our outline. Pure math, so it's tested
/// without a LiDAR phone.
enum RoomPlanConverter {
    static func draft(walls: [WallSegment], openings: [OpeningSegment]) -> RoomDraft? {
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
        return try? RoomDraftParser.parse(data)
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
        return RoomPlanConverter.draft(walls: walls, openings: segments)
    }
}
