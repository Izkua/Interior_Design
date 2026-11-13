import SwiftUI
import RealityKit
import Combine

/// A small turning view of a 3D model (AI-made GLB, or a USDZ scan or
/// import). Drag sideways to turn it yourself.
struct ModelPreview: UIViewRepresentable {
    let data: Data

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor(Theme.surfaceAlt))
        context.coordinator.attach(to: view)
        context.coordinator.show(data)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        if context.coordinator.shown != data { context.coordinator.show(data) }
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var view: ARView?
        private let anchor = AnchorEntity(world: .zero)
        private let turntable = Entity()
        private var updates: Cancellable?
        private var spinning = true
        private(set) var shown: Data?
        private var camera: PerspectiveCamera?

        func attach(to view: ARView) {
            self.view = view
            view.scene.addAnchor(anchor)
            anchor.addChild(turntable)
            let key = DirectionalLight()
            key.light.intensity = 3000
            key.look(at: .zero, from: [1, 2, 2], relativeTo: nil)
            anchor.addChild(key)
            let fill = DirectionalLight()
            fill.light.intensity = 1200
            fill.look(at: .zero, from: [-2, 1, -1], relativeTo: nil)
            anchor.addChild(fill)
            updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                guard let self, self.spinning else { return }
                self.turntable.orientation = simd_quatf(angle: Float(event.deltaTime) * 0.5, axis: [0, 1, 0]) * self.turntable.orientation
            }
            view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragged(_:))))
        }

        func show(_ data: Data) {
            shown = data
            turntable.children.removeAll()
            Task {
                guard let model = await Self.load(data) else { return }
                // Center the model on the turntable, standing on it.
                let bounds = model.visualBounds(relativeTo: nil)
                model.position -= [bounds.center.x, bounds.min.y, bounds.center.z]
                turntable.addChild(model)
                let radius = max(simd_length(bounds.extents) / 2, 0.05)
                let camera = PerspectiveCamera()
                camera.camera.fieldOfViewInDegrees = 40
                let target = SIMD3<Float>(0, bounds.extents.y / 2, 0)
                camera.look(at: target, from: target + SIMD3(0, radius * 0.9, radius * 2.6), relativeTo: nil)
                self.camera?.removeFromParent()
                self.camera = camera
                anchor.addChild(camera)
            }
        }

        @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
            spinning = gesture.state == .ended || gesture.state == .cancelled
            let dx = Float(gesture.translation(in: gesture.view).x)
            gesture.setTranslation(.zero, in: gesture.view)
            turntable.orientation = simd_quatf(angle: dx * 0.01, axis: [0, 1, 0]) * turntable.orientation
        }

        /// GLB (AI) models are stood up straight first, as in the room view.
        static func load(_ data: Data) async -> Entity? {
            if GLBModel.isGLB(data) {
                guard let parsed = try? await Task.detached(operation: {
                    var model = try GLBModel(data: data)
                    model.standUp()
                    return model
                }).value else { return nil }
                return try? parsed.entity()
            }
            return ARPlaceController.loadModel(data)
        }
    }
}
