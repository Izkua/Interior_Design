import SwiftUI
import ARKit
import SceneKit

/// Measuring with the camera in AR. Works on any iPhone with ARKit world
/// tracking (no LiDAR needed): ARKit finds flat surfaces as you move the
/// phone, and taps are placed on them.
///
/// Only offered when `ARMeasure.isAvailable`, so it never shows in the
/// Simulator.
enum ARMeasure {
    static var isAvailable: Bool { ARWorldTrackingConfiguration.isSupported }
}

/// Measure width, depth, and height one after another: aim the dot at one
/// end, tap "Set point", aim at the other end, tap again.
struct ARMeasureView: View {
    /// Starting values (the type's usual size), in cm.
    let start: (width: Double, depth: Double, height: Double)
    let onDone: (_ width: Double, _ depth: Double, _ height: Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var measured: [Double] = []
    @State private var firstPointSet = false
    @State private var liveDistance: Double?
    @State private var coordinator = ARMeasureCoordinator()

    private let names = ["width", "depth", "height"]

    var body: some View {
        ZStack {
            ARViewContainer(coordinator: coordinator)
                .ignoresSafeArea()

            // The aiming dot in the middle of the screen.
            Circle()
                .stroke(.white, lineWidth: 2)
                .background(Circle().fill(Theme.accent.opacity(0.6)))
                .frame(width: 18, height: 18)

            VStack {
                Text(instruction)
                    .font(Typography.headline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.top, Theme.Space.lg)
                Spacer()
                if let liveDistance {
                    Text(Length.formatFurniture(liveDistance, system: UnitSystem.deviceDefault))
                        .font(Typography.title)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                HStack(spacing: Theme.Space.sm) {
                    PrimaryButton(title: "Cancel", style: .tinted) { dismiss() }
                    PrimaryButton(title: firstPointSet ? "Set end" : "Set start", action: setPoint)
                }
                .padding(Theme.Space.md)
            }
        }
        .onAppear {
            coordinator.onLiveDistance = { liveDistance = $0 }
        }
    }

    private var instruction: String {
        guard measured.count < names.count else { return "Done" }
        let name = names[measured.count]
        return firstPointSet ? "Aim at the other end of the \(name)" : "Aim at one end of the \(name)"
    }

    private func setPoint() {
        if !firstPointSet {
            firstPointSet = coordinator.setStart()
            return
        }
        guard let distance = coordinator.finish() else { return }
        measured.append(distance)
        firstPointSet = false
        liveDistance = nil
        if measured.count == names.count {
            onDone(measured[0], measured[1], measured[2])
            dismiss()
        }
    }
}

/// Runs the AR session and turns screen taps into points in the room.
final class ARMeasureCoordinator: NSObject, ARSCNViewDelegate {
    weak var view: ARSCNView?
    var onLiveDistance: ((Double?) -> Void)?
    private var start: simd_float3?

    func attach(_ view: ARSCNView) {
        self.view = view
        view.delegate = self
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        view.session.run(configuration)
    }

    /// The point on a real surface under the screen's center, if ARKit has
    /// found one there.
    private func pointUnderCenter() -> simd_float3? {
        guard let view else { return nil }
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        guard let query = view.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .any),
              let hit = view.session.raycast(query).first else { return nil }
        let t = hit.worldTransform.columns.3
        return simd_float3(t.x, t.y, t.z)
    }

    func setStart() -> Bool {
        start = pointUnderCenter()
        return start != nil
    }

    /// The distance from the start point, in centimeters.
    func finish() -> Double? {
        guard let start, let end = pointUnderCenter() else { return nil }
        self.start = nil
        return Double(simd_distance(start, end)) * 100
    }

    // Updates the live distance about 60 times a second while aiming.
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let start else { return }
        DispatchQueue.main.async {
            let distance = self.pointUnderCenter().map { Double(simd_distance(start, $0)) * 100 }
            self.onLiveDistance?(distance)
        }
    }

    func stop() {
        view?.session.pause()
    }
}

private struct ARViewContainer: UIViewRepresentable {
    let coordinator: ARMeasureCoordinator

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        coordinator.attach(view)
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {}

    static func dismantleUIView(_ view: ARSCNView, coordinator: ()) {
        view.session.pause()
    }
}
