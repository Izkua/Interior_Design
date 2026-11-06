import SwiftUI
import SwiftData
import ARKit
import RealityKit
import Combine

/// "See it in my room": stands furniture in the real room as true-size 3D
/// stand-ins, through the camera. Works on any iPhone with ARKit (it finds
/// the floor by plane detection; no LiDAR needed). Everything runs on the
/// phone.
///
/// Aim at the floor, tap Place, then drag a piece with one finger to move
/// it and twist with two fingers to turn it. Tap a piece to pick it.
struct ARPlaceView: View {
    /// What to place first. More can be added from saved items.
    let start: [ARPiece]

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Item.createdAt) private var items: [Item]
    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue
    @State private var controller = ARPlaceController()

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    static var isAvailable: Bool { ARWorldTrackingConfiguration.isSupported }

    var body: some View {
        ZStack {
            ARContainer(controller: controller)
                .ignoresSafeArea()

            VStack(spacing: Theme.Space.sm) {
                topBar
                Spacer()
                if let hint = controller.hint {
                    Text(hint)
                        .font(Typography.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.55), in: Capsule())
                        .transition(.opacity)
                }
                bottomPanel
            }
            .padding(Theme.Space.md)
        }
        .animation(.easeInOut(duration: 0.2), value: controller.hint)
        .onAppear { controller.queue(start) }
        .statusBarHidden()
    }

    // MARK: Top

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: Theme.minTap, height: Theme.minTap)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close")
            Spacer()
            Text("True size")
                .font(Typography.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityLabel("Pieces are shown at their true size")
            Spacer()
            addMenu
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private var addMenu: some View {
        Menu {
            if items.isEmpty {
                Text("No saved items yet")
            }
            ForEach(items) { item in
                Button {
                    controller.queue([ARPiece(item: item)])
                } label: {
                    Label(item.name, systemImage: item.type.symbol)
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: Theme.minTap, height: Theme.minTap)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Add one of your items")
    }

    // MARK: Bottom

    @ViewBuilder
    private var bottomPanel: some View {
        if let next = controller.pending.first {
            VStack(spacing: Theme.Space.sm) {
                pieceLine(next)
                PrimaryButton(title: controller.floorFound ? "Place here" : "Looking for the floor…", systemImage: "arrow.down.to.line") {
                    controller.placePending()
                }
                .disabled(!controller.floorFound)
                .opacity(controller.floorFound ? 1 : 0.6)
            }
            .padding(Theme.Space.md)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        } else if let selected = controller.selected {
            VStack(spacing: Theme.Space.sm) {
                pieceLine(selected)
                HStack(spacing: Theme.Space.sm) {
                    panelButton("Turn", systemImage: "rotate.right") { controller.turnSelected() }
                    panelButton("Copy", systemImage: "plus.square.on.square") { controller.queue([selected.withNewID()]) }
                    panelButton("Remove", systemImage: "trash", role: .destructive) { controller.removeSelected() }
                }
            }
            .padding(Theme.Space.md)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        } else if controller.placedCount > 0 {
            Text("Drag to move, twist with two fingers to turn. Tap a piece to change it.")
                .font(Typography.caption)
                .multilineTextAlignment(.center)
                .padding(Theme.Space.md)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    private func pieceLine(_ piece: ARPiece) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: piece.type.symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(piece.name)
                    .font(Typography.headline)
                    .lineLimit(1)
                Text(Length.formatDimensions(width: piece.widthCm, depth: piece.depthCm, height: piece.heightCm, system: unit) + " (W × D × H)")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            if piece.isEstimated { Tag(text: "Estimated") }
        }
    }

    private func panelButton(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(Typography.subheadline)
                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(role == .destructive ? Theme.danger : Theme.textPrimary)
    }
}

private extension ARPiece {
    func withNewID() -> ARPiece {
        var copy = self
        copy.id = UUID()
        return copy
    }
}

// MARK: - The camera view

private struct ARContainer: UIViewRepresentable {
    let controller: ARPlaceController

    func makeUIView(context: Context) -> ARView {
        controller.makeView()
    }

    func updateUIView(_ view: ARView, context: Context) {}

    static func dismantleUIView(_ view: ARView, coordinator: ()) {
        view.session.pause()
    }
}

/// Runs the AR scene: finds the floor under the aiming point, places
/// pieces there, and keeps track of which one is picked.
@Observable
final class ARPlaceController: NSObject {
    /// Pieces waiting to be placed, first one next.
    private(set) var pending: [ARPiece] = []
    /// The piece the person last tapped (or just placed).
    private(set) var selected: ARPiece?
    private(set) var floorFound = false
    private(set) var placedCount = 0
    /// A short instruction over the camera, or nil.
    private(set) var hint: String? = "Move your phone slowly to find the floor."

    @ObservationIgnored private weak var arView: ARView?
    @ObservationIgnored private var footprint: ModelEntity?
    @ObservationIgnored private var footprintAnchor = AnchorEntity(world: .zero)
    @ObservationIgnored private var placed: [UUID: (piece: ARPiece, entity: ModelEntity)] = [:]
    @ObservationIgnored private var updates: Cancellable?
    @ObservationIgnored private var aim: simd_float4x4?

    func makeView() -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.renderOptions.insert(.disableMotionBlur)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        view.session.run(config)

        let coaching = ARCoachingOverlayView()
        coaching.session = view.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(coaching)

        view.scene.addAnchor(footprintAnchor)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in self?.updateAim() }
        arView = view
        if let first = pending.first { showFootprint(for: first) }
        return view
    }

    // MARK: Placing

    func queue(_ pieces: [ARPiece]) {
        guard !pieces.isEmpty else { return }
        let wasEmpty = pending.isEmpty
        pending.append(contentsOf: pieces)
        if wasEmpty, let first = pending.first { showFootprint(for: first) }
        for piece in pieces {
            if let url = piece.imageURL {
                Task { [weak self] in
                    guard let colors = await ARPiece.colors(fromImageAt: url, type: piece.type) else { return }
                    await MainActor.run { self?.recolor(piece.id, colors) }
                }
            }
        }
    }

    func placePending() {
        guard let aim, let arView, !pending.isEmpty else { return }
        let piece = pending.removeFirst()
        let entity = Self.makeEntity(for: piece)
        let anchor = AnchorEntity(world: aim)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
        arView.installGestures([.translation, .rotation], for: entity)
        placed[piece.id] = (piece, entity)
        placedCount = placed.count
        select(piece.id)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let next = pending.first { showFootprint(for: next) } else { footprint?.isEnabled = false }
    }

    func turnSelected() {
        guard let id = selected?.id, let entity = placed[id]?.entity else { return }
        var transform = entity.transform
        transform.rotation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0]) * transform.rotation
        entity.move(to: transform, relativeTo: entity.parent, duration: 0.25)
    }

    func removeSelected() {
        guard let id = selected?.id, let entity = placed.removeValue(forKey: id)?.entity else { return }
        entity.anchor?.removeFromParent()
        placedCount = placed.count
        selected = nil
    }

    private func select(_ id: UUID?) {
        for (key, value) in placed {
            value.entity.findEntity(named: "selection")?.isEnabled = key == id
        }
        selected = id.flatMap { placed[$0]?.piece }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let arView else { return }
        let point = gesture.location(in: arView)
        var hit = arView.entity(at: point)
        while let current = hit, !placed.values.contains(where: { $0.entity === current }) {
            hit = current.parent
        }
        let id = placed.first { $0.value.entity === hit }?.key
        // Tapping empty floor while a piece is waiting places it there.
        if id == nil, !pending.isEmpty {
            placePending()
            return
        }
        select(id)
    }

    private func recolor(_ id: UUID, _ colors: FurnitureColors) {
        if let index = pending.firstIndex(where: { $0.id == id }) {
            pending[index].colors = colors
        }
        if var entry = placed[id] {
            entry.piece.colors = colors
            placed[id] = entry
            Self.paint(entry.entity, colors)
            if selected?.id == id { selected = entry.piece }
        }
    }

    // MARK: Aiming at the floor

    private func updateAim() {
        guard let arView, !pending.isEmpty else { return }
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        guard let result = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .horizontal).first else {
            if floorFound { floorFound = false }
            footprint?.isEnabled = false
            if hint == nil { hint = "Point at the floor." }
            return
        }
        // Face the piece's front toward the camera.
        let position = simd_make_float3(result.worldTransform.columns.3)
        let camera = arView.cameraTransform.translation
        let toCamera = simd_float2(camera.x - position.x, camera.z - position.z)
        let yaw = atan2(toCamera.x, toCamera.y)
        var transform = Transform(rotation: simd_quatf(angle: yaw, axis: [0, 1, 0]), translation: position)
        // Smooth small jumps so the outline doesn't shake.
        if let current = footprint?.transform, footprint?.isEnabled == true,
           simd_distance(current.translation, position) < 0.3 {
            transform.translation = simd_mix(current.translation, position, simd_float3(repeating: 0.4))
            transform.rotation = simd_slerp(current.rotation, transform.rotation, 0.4)
        }
        footprint?.transform = transform
        footprint?.isEnabled = true
        aim = transform.matrix
        if !floorFound { floorFound = true }
        if hint != nil { hint = nil }
    }

    /// A flat outline of the next piece's true footprint, under the aiming point.
    private func showFootprint(for piece: ARPiece) {
        footprint?.removeFromParent()
        let w = Float(piece.widthCm / 100), d = Float(piece.depthCm / 100)
        let outline = Self.outline(width: w, depth: d, line: 0.012, color: .white)
        let fill = ModelEntity(mesh: .generatePlane(width: w, depth: d), materials: [Self.seeThrough(.white, 0.18)])
        outline.addChild(fill)
        // An arrow-like bar along the front edge, so you can tell which way it faces.
        let front = ModelEntity(mesh: .generateBox(size: [w * 0.5, 0.004, 0.03]), materials: [UnlitMaterial(color: .white)])
        front.position = [0, 0.002, d / 2 + 0.04]
        outline.addChild(front)
        outline.isEnabled = false
        footprintAnchor.addChild(outline)
        footprint = outline
    }

    // MARK: Building the 3D stand-in

    static func makeEntity(for piece: ARPiece) -> ModelEntity {
        let root = ModelEntity()
        for part in piece.parts {
            let mesh = MeshResource.generateBox(size: part.size, cornerRadius: part.cornerRadius)
            let child = ModelEntity(mesh: mesh, materials: [material(for: part.tone, piece.colors)])
            child.name = "\(part.tone)"
            child.position = part.center
            root.addChild(child)
        }
        let w = Float(piece.widthCm / 100), d = Float(piece.depthCm / 100), h = Float(piece.heightCm / 100)
        // A soft dark patch under it, so it looks like it stands on the floor.
        let shadow = ModelEntity(mesh: .generatePlane(width: w + 0.06, depth: d + 0.06, cornerRadius: 0.03),
                                 materials: [seeThrough(.black, 0.28)])
        shadow.position.y = 0.002
        root.addChild(shadow)
        // Shown while the piece is picked.
        let selection = outline(width: w + 0.06, depth: d + 0.06, line: 0.015, color: UIColor(Theme.accent))
        selection.name = "selection"
        selection.position.y = 0.004
        selection.isEnabled = false
        root.addChild(selection)
        // One box to grab for dragging and turning.
        root.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: [w, max(h, 0.05), d]).offsetBy(translation: [0, max(h, 0.05) / 2, 0])])
        return root
    }

    static func paint(_ root: Entity, _ colors: FurnitureColors) {
        for child in root.children {
            guard let model = child as? ModelEntity else { continue }
            let tone: FurnitureShape.Tone? = switch child.name {
            case "main": .main
            case "accent": .accent
            case "light": .light
            default: nil
            }
            if let tone { model.model?.materials = [material(for: tone, colors)] }
        }
    }

    private static func material(for tone: FurnitureShape.Tone, _ colors: FurnitureColors) -> RealityKit.Material {
        let color: UIColor
        switch tone {
        case .main: color = colors.main.uiColor
        case .accent: color = colors.accent.uiColor
        case .light: color = UIColor(white: 0.95, alpha: 1)
        }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: 0.85)
        material.metallic = .init(floatLiteral: 0)
        return material
    }

    private static func seeThrough(_ color: UIColor, _ opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    /// A rectangle drawn with four thin bars, lying on the floor.
    private static func outline(width w: Float, depth d: Float, line: Float, color: UIColor) -> ModelEntity {
        let root = ModelEntity()
        let material = UnlitMaterial(color: color)
        let bars: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([w, 0.003, line], [0, 0, d / 2]), ([w, 0.003, line], [0, 0, -d / 2]),
            ([line, 0.003, d], [w / 2, 0, 0]), ([line, 0.003, d], [-w / 2, 0, 0]),
        ]
        for (size, position) in bars {
            let bar = ModelEntity(mesh: .generateBox(size: size), materials: [material])
            bar.position = position
            root.addChild(bar)
        }
        return root
    }
}
