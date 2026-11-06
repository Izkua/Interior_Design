import SwiftUI
import ARKit
import SceneKit
import simd

/// Turning traced floor points into a room outline. Pure math, so it's
/// tested without a phone.
enum ARRoomTrace {
    /// Within this distance of the first corner (in meters), a new corner
    /// closes the room instead.
    static let closeDistance: Float = 0.3

    /// True when `point` is close enough to the first corner to close the room.
    static func closes(_ corners: [simd_float3], with point: simd_float3) -> Bool {
        guard corners.count >= 3, let first = corners.first else { return false }
        return simd_distance(flat(first), flat(point)) < closeDistance
    }

    /// A door or window marked by its two edges on the floor.
    struct Opening {
        var kind: FeatureKind
        var a: simd_float3
        var b: simd_float3
    }

    /// The outline as a draft for the room builder. Corners are in meters
    /// on the floor (ARKit's x and z); the draft is in cm. Walls are marked
    /// as estimated, so the person checks them.
    static func draft(corners: [simd_float3], openings: [Opening] = []) -> RoomDraft? {
        guard corners.count >= 3 else { return nil }
        let points = corners.map { Point2D(x: Double($0.x) * 100, y: Double($0.z) * 100) }
        var features: [[String: Any]] = []
        for opening in openings {
            let middle = Point2D(x: Double(opening.a.x + opening.b.x) * 50, y: Double(opening.a.z + opening.b.z) * 50)
            let hit = PlanGeometry.nearestWall(to: middle, corners: points)
            let width = Double(simd_distance(flat(opening.a), flat(opening.b))) * 100
            features.append(["kind": opening.kind.rawValue, "wall": hit.wall, "offsetCm": hit.offset, "widthCm": width])
        }
        let json: [String: Any] = [
            "corners": points.map { ["x": $0.x, "y": $0.y] },
            // Traced by hand with the camera: close, but worth a check.
            "walls": points.map { _ in ["seen": true, "confidence": 0.7] },
            "features": features,
            "closed": true,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        // The parser fixes the order and origin and checks for crossing walls.
        return try? RoomDraftParser.parse(data)
    }

    /// Length along the floor between two points, in cm.
    static func lengthCm(_ a: simd_float3, _ b: simd_float3) -> Double {
        Double(simd_distance(flat(a), flat(b))) * 100
    }

    private static func flat(_ p: simd_float3) -> simd_float3 { simd_float3(p.x, 0, p.z) }

    // MARK: Snap to right angles

    /// Where a new corner goes with snapping on: the wall from the last
    /// corner keeps its length but turns to a regular angle (90°, or 45°)
    /// from the first wall, if it's within 15° of one. The first two
    /// corners are placed as aimed. Also returns the turn from the
    /// previous wall in degrees when it snapped (for the badge).
    static func snapped(_ point: simd_float3, after corners: [simd_float3]) -> (point: simd_float3, turn: Int?) {
        guard corners.count >= 2, let last = corners.last else { return (point, nil) }
        let d = point - last
        let length = Double((d.x * d.x + d.z * d.z).squareRoot())
        guard length > 0.05 else { return (point, nil) }
        let first = corners[1] - corners[0]
        let base = Double(atan2(first.z, first.x))
        let previous = corners[corners.count - 1] - corners[corners.count - 2]
        let snap = RoomStraightener.snap(Double(atan2(d.z, d.x)), base: base)
        guard snap.snapped else { return (point, nil) }
        let turn = RoomStraightener.turnDegrees(from: Double(atan2(previous.z, previous.x)), to: snap.angle)
        let moved = simd_float3(last.x + Float(cos(snap.angle) * length), point.y, last.z + Float(sin(snap.angle) * length))
        return (moved, turn)
    }
}

/// Trace a room with the camera: lock onto the floor, then add each corner
/// where a wall meets the floor, going around the room. Then, if you like,
/// mark doors and windows by their two edges.
struct ARRoomTraceView: View {
    let onDone: (RoomDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model = ARTraceModel()
    @State private var corners: [simd_float3] = []
    @State private var openings: [ARRoomTrace.Opening] = []
    @State private var closed = false
    /// While marking a door or window: what, and its first edge if set.
    @State private var marking: FeatureKind?
    @State private var firstEdge: simd_float3?
    @State private var problem: String?
    @State private var tapCount = 0
    /// Walls meet at right angles (most rooms). Off for angled walls.
    @AppStorage("trace.snapAngles") private var squareCorners = true

    private var unit: UnitSystem { UnitSystem.deviceDefault }

    var body: some View {
        ZStack {
            ARTraceContainer(model: model)
                .ignoresSafeArea()

            Circle()
                .stroke(.white, lineWidth: 2)
                .background(Circle().fill((model.onFloor ? Theme.accent : Color.gray).opacity(0.8)))
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(spacing: Theme.Space.sm) {
                Text(instruction)
                    .font(Typography.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.top, Theme.Space.sm)
                if !closed && marking == nil {
                    Toggle(isOn: $squareCorners) {
                        Text("Snap to right angles")
                            .font(Typography.subheadline)
                            .foregroundStyle(.white)
                    }
                    .tint(Theme.accent)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.horizontal, Theme.Space.md)
                    .accessibilityHint("Turns walls that are nearly square to exactly 90 degrees, or 45. Turn off for odd-angled walls.")
                    .onChange(of: squareCorners) { _, on in model.squareCorners = on }
                }
                if let problem = problem ?? model.problem {
                    Text(problem)
                        .font(Typography.subheadline)
                        .foregroundStyle(.yellow)
                        .padding(8)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                }
                if let live = model.liveLengthCm, !closed || firstEdge != nil {
                    HStack(spacing: Theme.Space.xs) {
                        Text(Length.formatFurniture(live, system: unit))
                            .font(Typography.title)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Theme.accent.opacity(0.9), in: Capsule())
                            .accessibilityLabel("This wall so far, \(Length.formatFurniture(live, system: unit))")
                        if let turn = model.liveTurn, marking == nil, turn != 0, turn != 180 {
                            Label("\(turn)°", systemImage: "angle")
                                .font(Typography.subheadline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.black.opacity(0.6), in: Capsule())
                                .accessibilityLabel("Snapped to \(turn) degrees")
                        }
                    }
                }
                Spacer()
                controls
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.bottom, Theme.Space.md)
            }
        }
        .sensoryFeedback(.impact, trigger: tapCount)
        .onAppear { model.squareCorners = squareCorners }
        .onDisappear { model.pause() }
    }

    // MARK: Words and buttons

    private var instruction: String {
        if !model.onFloor { return "Point at the floor and move your phone slowly until the dot turns green." }
        if let marking {
            let name = marking == .door ? "door" : "window"
            return firstEdge == nil
                ? "Put the dot on the floor at one edge of the \(name), against the wall, then tap Set edge."
                : "Now the other edge of the \(name), then tap Set edge."
        }
        if closed { return "Room traced. Add doors and windows if you like, or tap Done." }
        switch corners.count {
        case 0: return "Stand in the room. Put the dot where a wall meets the floor in one corner, then tap Add corner."
        case 1, 2: return "Go around the room: put the dot in the next corner and tap Add corner."
        default: return "Next corner, or aim back at the first corner (or tap Close room) to finish."
        }
    }

    @ViewBuilder
    private var controls: some View {
        if closed && marking == nil {
            VStack(spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    PrimaryButton(title: "Add a door", systemImage: "door.left.hand.open", style: .tinted) { marking = .door; firstEdge = nil }
                    PrimaryButton(title: "Add a window", systemImage: "window.casement", style: .tinted) { marking = .window; firstEdge = nil }
                }
                PrimaryButton(title: "Done", systemImage: "checkmark") { finish() }
                Button("Back to corners") { closed = false; model.setCorners(corners, closed: false) }
                    .font(Typography.subheadline)
                    .foregroundStyle(.white)
                    .frame(minHeight: Theme.minTap)
            }
        } else if marking != nil {
            HStack(spacing: Theme.Space.sm) {
                PrimaryButton(title: "Cancel", style: .tinted) { marking = nil; firstEdge = nil; model.setStart(nil) }
                PrimaryButton(title: "Set edge", action: setEdge)
                    .disabled(!model.onFloor)
                    .opacity(model.onFloor ? 1 : 0.5)
            }
        } else {
            VStack(spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    PrimaryButton(title: corners.isEmpty ? "Cancel" : "Undo", style: .tinted) {
                        if corners.isEmpty { dismiss() } else { removeLastCorner() }
                    }
                    PrimaryButton(title: "Add corner", systemImage: "plus", action: addCorner)
                        .disabled(!model.onFloor)
                        .opacity(model.onFloor ? 1 : 0.5)
                }
                if corners.count >= 3 {
                    PrimaryButton(title: "Close room", systemImage: "checkmark.circle", style: .tinted) { close() }
                }
            }
        }
    }

    // MARK: Actions

    private func addCorner() {
        guard let aimed = model.steadyPoint() else { return }
        if ARRoomTrace.closes(corners, with: aimed) { close(); return }
        let point = squareCorners ? ARRoomTrace.snapped(aimed, after: corners).point : aimed
        corners.append(point)
        tapCount += 1
        problem = nil
        model.setCorners(corners, closed: false)
        UIAccessibility.post(notification: .announcement, argument: "Corner \(corners.count) added")
    }

    private func removeLastCorner() {
        corners.removeLast()
        model.setCorners(corners, closed: false)
    }

    private func close() {
        guard corners.count >= 3 else { return }

        guard ARRoomTrace.draft(corners: corners) != nil else {
            problem = "Some walls cross each other. Undo a corner and try again, going around the room in order."
            return
        }
        closed = true
        tapCount += 1
        model.setCorners(corners, closed: true)
    }

    private func setEdge() {
        guard let point = model.steadyPoint(), let kind = marking else { return }
        if let first = firstEdge {
            openings.append(ARRoomTrace.Opening(kind: kind, a: first, b: point))
            model.addOpening(first, point, color: kind == .door ? .systemOrange : .systemBlue)
            marking = nil
            firstEdge = nil
            model.setStart(nil)
        } else {
            firstEdge = point
            model.setStart(point)
        }
        tapCount += 1
    }

    private func finish() {
        guard let draft = ARRoomTrace.draft(corners: corners, openings: openings) else {
            problem = "Couldn't make a room from those corners. Undo and try again."
            return
        }
        onDone(draft)
        dismiss()
    }
}

/// The AR session for tracing: floor detection, the point under the dot,
/// and drawing corners and walls in the room.
@MainActor
@Observable
final class ARTraceModel: NSObject, ARSessionDelegate, ARSCNViewDelegate {
    private(set) var onFloor = false
    private(set) var liveLengthCm: Double?
    /// The snapped turn from the previous wall, for the "90°" badge.
    private(set) var liveTurn: Int?
    private(set) var problem: String?

    @ObservationIgnored weak var view: ARSCNView?
    @ObservationIgnored private var recent: [simd_float3] = []
    @ObservationIgnored private var lastCorner: simd_float3?
    @ObservationIgnored private var outlineNodes: [SCNNode] = []
    @ObservationIgnored private var openingNodes: [SCNNode] = []
    @ObservationIgnored private var liveNode: SCNNode?
    /// Corners so far, so the live line can show where a squared corner lands.
    @ObservationIgnored private var traced: [simd_float3] = []
    @ObservationIgnored var squareCorners = true

    func attach(_ view: ARSCNView) {
        self.view = view
        view.delegate = self
        view.session.delegate = self
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        let coaching = ARCoachingOverlayView()
        coaching.session = view.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(coaching)
        NSLayoutConstraint.activate([
            coaching.topAnchor.constraint(equalTo: view.topAnchor),
            coaching.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            coaching.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            coaching.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func pause() { view?.session.pause() }

    /// The floor under the dot: the found floor, treated as endless, so
    /// corners far away still land on it.
    private func floorPoint() -> simd_float3? {
        guard let view, view.bounds.width > 0 else { return nil }
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        for target in [ARRaycastQuery.Target.existingPlaneInfinite, .estimatedPlane] {
            if let query = view.raycastQuery(from: center, allowing: target, alignment: .horizontal),
               let hit = view.session.raycast(query).first {
                let t = hit.worldTransform.columns.3
                return simd_float3(t.x, t.y, t.z)
            }
        }
        return nil
    }

    /// The middle reading of the last few frames, so a shaky tap still
    /// lands where you aimed.
    func steadyPoint() -> simd_float3? {
        ARMeasure.median(recent) ?? floorPoint()
    }

    /// Where the live wall starts (the last corner or a door's first edge).
    func setStart(_ point: simd_float3?) {
        lastCorner = point
        if point == nil { liveLengthCm = nil }
    }

    /// Draws the corners and walls traced so far.
    func setCorners(_ corners: [simd_float3], closed: Bool) {
        outlineNodes.forEach { $0.removeFromParentNode() }
        outlineNodes.removeAll()
        guard let root = view?.scene.rootNode else { return }
        for corner in corners {
            let dot = SCNNode(geometry: SCNSphere(radius: 0.02))
            dot.geometry?.firstMaterial?.diffuse.contents = UIColor(Theme.accent)
            dot.simdPosition = corner
            root.addChildNode(dot)
            outlineNodes.append(dot)
        }
        let pairs = closed ? corners.indices.map { (corners[$0], corners[($0 + 1) % corners.count]) }
                           : zip(corners, corners.dropFirst()).map { ($0, $1) }
        for (a, b) in pairs {
            outlineNodes.append(contentsOf: line(from: a, to: b, color: UIColor(Theme.accent), label: true))
        }
        traced = closed ? [] : corners
        lastCorner = closed ? nil : corners.last
        if closed { liveLengthCm = nil }
    }

    func addOpening(_ a: simd_float3, _ b: simd_float3, color: UIColor) {
        openingNodes.append(contentsOf: line(from: a, to: b, color: color, label: false, thickness: 0.012))
    }

    private func line(from a: simd_float3, to b: simd_float3, color: UIColor, label: Bool, thickness: CGFloat = 0.006) -> [SCNNode] {
        guard let root = view?.scene.rootNode, simd_distance(a, b) > 0.01 else { return [] }
        let rod = SCNCylinder(radius: thickness, height: CGFloat(simd_distance(a, b)))
        rod.firstMaterial?.diffuse.contents = color
        let node = SCNNode(geometry: rod)
        node.simdPosition = (a + b) / 2
        node.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: simd_normalize(b - a))
        root.addChildNode(node)
        var nodes = [node]
        if label {
            let text = SCNText(string: Length.format(ARRoomTrace.lengthCm(a, b), system: UnitSystem.deviceDefault), extrusionDepth: 0)
            text.font = .systemFont(ofSize: 10, weight: .bold)
            text.firstMaterial?.diffuse.contents = UIColor.white
            text.firstMaterial?.isDoubleSided = true
            let tag = SCNNode(geometry: text)
            tag.scale = SCNVector3(0.006, 0.006, 0.006)
            tag.simdPosition = (a + b) / 2 + simd_float3(0, 0.05, 0)
            tag.constraints = [SCNBillboardConstraint()]
            root.addChildNode(tag)
            nodes.append(tag)
        }
        return nodes
    }

    // MARK: Every frame

    nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        Task { @MainActor in self.update() }
    }

    private func update() {
        let point = floorPoint()
        if onFloor != (point != nil) { onFloor = point != nil }
        if let point {
            recent.append(point)
            if recent.count > 20 { recent.removeFirst(recent.count - 20) }
        } else {
            recent.removeAll()
        }
        liveNode?.removeFromParentNode()
        liveNode = nil
        guard let start = lastCorner, var point else { return }
        // Show the wall where it will really go, squared or not.
        if squareCorners, !traced.isEmpty, start == traced.last {
            let snap = ARRoomTrace.snapped(point, after: traced)
            point = snap.point
            if snap.turn != liveTurn { liveTurn = snap.turn }
        } else if liveTurn != nil { liveTurn = nil }
        let length = (ARRoomTrace.lengthCm(start, point) * 2).rounded() / 2
        if length != liveLengthCm { liveLengthCm = length }
        if let node = line(from: start, to: point, color: UIColor.white.withAlphaComponent(0.8), label: false, thickness: 0.004).first {
            liveNode = node
        }
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let message: String?
        switch camera.trackingState {
        case .limited(.excessiveMotion): message = "Move your phone a bit more slowly."
        case .limited(.insufficientFeatures): message = "Too little detail to track. Turn on a light or aim at a patterned floor or rug."
        default: message = nil
        }
        Task { @MainActor in self.problem = message }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let denied = (error as? ARError)?.code == .cameraUnauthorized
        Task { @MainActor in
            self.problem = denied
                ? "Camera access is off. Allow it in Settings → Interior Design → Camera."
                : "The camera couldn't start. Close this screen and try again."
        }
    }
}

private struct ARTraceContainer: UIViewRepresentable {
    let model: ARTraceModel

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        model.attach(view)
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {}

    static func dismantleUIView(_ view: ARSCNView, coordinator: ()) {
        view.session.pause()
    }
}
