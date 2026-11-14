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
                if let hint = controller.message ?? controller.hint {
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
        .animation(.easeInOut(duration: 0.2), value: controller.message ?? controller.hint)
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
            if controller.hasPhotos {
                Picker("Show pieces as", selection: $controller.look) {
                    Text("Real").tag(ARPlaceController.Look.photo)
                    Text("Shape").tag(ARPlaceController.Look.shape)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                Text("True size")
                    .font(Typography.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityLabel("Pieces are shown at their true size")
            }
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
        if let step = controller.wallMarkStep {
            // Marking a plain wall by where it meets the floor.
            VStack(spacing: Theme.Space.sm) {
                Text(step == 0
                     ? "Aim the dot at the floor right where the wall meets it, near the LEFT end of where the art could go. Tap Mark."
                     : "Now aim at the same line near the RIGHT end, and tap Mark.")
                    .font(Typography.subheadline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Space.sm) {
                    panelButton("Cancel", systemImage: "xmark") { controller.cancelWallMarking() }
                    PrimaryButton(title: controller.floorUnderDot ? "Mark" : "Find the floor…", systemImage: "mappin.and.ellipse") {
                        controller.markWallPoint()
                    }
                    .disabled(!controller.floorUnderDot)
                    .opacity(controller.floorUnderDot ? 1 : 0.6)
                }
            }
            .padding(Theme.Space.md)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        } else if let next = controller.pending.first {
            VStack(spacing: Theme.Space.sm) {
                pieceLine(next)
                PrimaryButton(title: controller.floorFound ? "Place here" : (next.goesOnWall ? "Looking for a wall…" : next.goesOnSurface ? "Looking for a table or desk…" : "Looking for the floor…"),
                              systemImage: next.goesOnWall ? "rectangle.portrait.on.rectangle.portrait" : "arrow.down.to.line") {
                    controller.placePending()
                }
                .disabled(!controller.floorFound)
                .opacity(controller.floorFound ? 1 : 0.6)
                if next.goesOnWall {
                    // Plain walls are hard to see without LiDAR; the floor
                    // line is easy, so the wall can be built from it.
                    Button {
                        controller.startWallMarking()
                    } label: {
                        Label(controller.hasMarkedWall ? "Mark another wall" : "Wall not found? Mark it on the floor", systemImage: "ruler")
                            .font(Typography.subheadline)
                            .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
            .padding(Theme.Space.md)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        } else if let selected = controller.selected {
            VStack(spacing: Theme.Space.sm) {
                pieceLine(selected)
                HStack(spacing: Theme.Space.sm) {
                    panelButton("Turn", systemImage: "rotate.right") { controller.turnSelected() }
                    panelButton("Copy", systemImage: "plus.square.on.square") { controller.copySelected() }
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
                Text(Length.formatDimensions(height: piece.heightCm, width: piece.widthCm, depth: piece.depthCm, system: unit) + " (H × W × D)")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            if piece.isEstimated { Tag(text: "Estimated") }
            if controller.aiModelIDs.contains(piece.id) { Tag(text: "AI-generated 3D") }
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
@MainActor
@Observable
final class ARPlaceController: NSObject {
    /// Pieces waiting to be placed, first one next.
    private(set) var pending: [ARPiece] = []
    /// The piece the person last tapped (or just placed).
    private(set) var selected: ARPiece?
    private(set) var floorFound = false
    private(set) var placedCount = 0
    /// A short instruction over the camera, or nil.
    private(set) var hint: String? = "Move your phone slowly so it can find surfaces."
    /// A message about the 3D model, shown over the floor hint.
    private(set) var message: String?
    /// True once at least one piece has a cut-out photo to show.
    private(set) var hasPhotos = false
    /// Marking a wall on the floor: 0 waiting for the left point, 1 for the
    /// right one; nil when not marking.
    private(set) var wallMarkStep: Int?
    private(set) var floorUnderDot = false
    private(set) var hasMarkedWall = false
    /// Walls the person marked along the floor: a point on each, and which
    /// way it faces (into the room).
    @ObservationIgnored private var markedWalls: [(point: SIMD3<Float>, normal: SIMD3<Float>, from: SIMD3<Float>, to: SIMD3<Float>)] = []
    @ObservationIgnored private var markStart: SIMD3<Float>?
    @ObservationIgnored private var floorAim: SIMD3<Float>?
    @ObservationIgnored private var markNodes: [Entity] = []
    @ObservationIgnored private let markAnchor = AnchorEntity(world: .zero)

    /// Pieces shown with an AI-made 3D model, which get a label saying so.
    private(set) var aiModelIDs: Set<UUID> = []
    /// Models already at true size and in place (sets sized by their table).
    @ObservationIgnored private var trueSizeIDs: Set<UUID> = []

    /// How pieces are drawn: their cut-out photo standing in the room, or
    /// the colored box shape.
    enum Look: Hashable { case photo, shape }
    var look: Look = .photo {
        didSet { applyLook() }
    }

    @ObservationIgnored private weak var arView: ARView?
    @ObservationIgnored private var footprint: ModelEntity?
    @ObservationIgnored private var footprintAnchor = AnchorEntity(world: .zero)
    @ObservationIgnored private var placed: [UUID: (piece: ARPiece, entity: ModelEntity)] = [:]
    @ObservationIgnored private var updates: Cancellable?
    @ObservationIgnored private var aim: simd_float4x4?
    /// Each piece's cut-out photo, once it's ready.
    @ObservationIgnored private var cutouts: [UUID: CGImage] = [:]
    /// Each piece's real 3D model, if it has one.
    @ObservationIgnored private var models: [UUID: Entity] = [:]

    func makeView() -> ARView {
        BillboardTag.registerComponent()
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.renderOptions.insert(.disableMotionBlur)
        let config = ARWorldTrackingConfiguration()
        // Walls too, for posters and other wall decor.
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        view.session.run(config)

        let coaching = ARCoachingOverlayView()
        coaching.session = view.session
        coaching.goal = .anyPlane
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(coaching)

        view.scene.addAnchor(footprintAnchor)
        view.scene.addAnchor(markAnchor)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        // Wall decor slides along the wall (the usual drag would lift it off).
        let slide = UIPanGestureRecognizer(target: self, action: #selector(slid(_:)))
        slide.delegate = self
        slide.maximumNumberOfTouches = 1
        view.addGestureRecognizer(slide)
        updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            self?.turnPhotosToCamera()
            self?.updateAim()
        }
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
        for piece in pieces where cutouts[piece.id] == nil && models[piece.id] == nil {
            if piece.goesOnWall {
                // Wall decor shows its photo flat on the wall (no 3D model).
            } else if let data = piece.modelData, piece.hasAIModel {
                // An AI model made from the person's own photo.
                Task { [weak self] in await self?.showAIModel(data, for: piece.id, isNew: false) }
            } else if let data = piece.modelData, let model = Self.loadModel(data) {
                // A real 3D model beats a cut-out photo.
                addModel(model, to: piece.id)
                continue
            }
            if let productID = piece.productID {
                Task { [weak self] in await self?.makeAIModel(productID, for: piece.id) }
            }
            if let png = piece.cutoutData, let chosen = UIImage(data: png)?.cgImage {
                // The person picked the cutout themselves.
                addCutout(chosen, to: piece.id)
                continue
            }
            Task { [weak self] in
                guard let photo = await piece.loadPhoto() else { return }
                // Saved items were colored from their photo already.
                let colors = piece.imageURL != nil ? PhotoColors.colors(from: photo, type: piece.type) : nil
                // A rug is shown flat with its whole photo; anything else
                // is lifted out of its background to stand up.
                let cutout = piece.type == .rug ? photo.cgImage : await PhotoCutout.cutout(from: photo)
                await MainActor.run {
                    if let colors { self?.recolor(piece.id, colors) }
                    if let cutout { self?.addCutout(cutout, to: piece.id) }
                }
            }
        }
    }

    func copySelected() {
        guard var copy = selected else { return }
        let original = copy.id
        copy.id = UUID()
        if let cutout = cutouts[original] {
            cutouts[copy.id] = cutout
        }
        if let model = models[original] {
            models[copy.id] = model
            if aiModelIDs.contains(original) { aiModelIDs.insert(copy.id) }
            if trueSizeIDs.contains(original) { trueSizeIDs.insert(copy.id) }
        }
        copy.productID = nil   // its model, if any, was copied above
        queue([copy])
    }

    func placePending() {
        guard let aim, let arView, !pending.isEmpty else { return }
        let piece = pending.removeFirst()
        if piece.goesOnWall {
            // Hangs flat on the wall: a thin panel, with its photo on the front.
            let entity = Self.makeWallEntity(for: piece, cutout: cutouts[piece.id])
            let anchor = AnchorEntity(world: aim)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
            placed[piece.id] = (piece, entity)
            placedCount = placed.count
            applyLook()
            select(piece.id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let next = pending.first { showFootprint(for: next) } else { footprint?.isEnabled = false }
            return
        }
        let entity = Self.makeEntity(for: piece)
        if let model = models[piece.id] {
            Self.addModel(model, of: piece, to: entity, stretch: aiModelIDs.contains(piece.id), asIs: trueSizeIDs.contains(piece.id))
        } else if let cutout = cutouts[piece.id] {
            Self.addPhoto(cutout, of: piece, to: entity)
        }
        let anchor = AnchorEntity(world: aim)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
        arView.installGestures([.translation, .rotation], for: entity)
        placed[piece.id] = (piece, entity)
        placedCount = placed.count
        applyLook()
        select(piece.id)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let next = pending.first { showFootprint(for: next) } else { footprint?.isEnabled = false }
    }

    func turnSelected() {
        guard let id = selected?.id, let entity = placed[id]?.entity else { return }
        var transform = entity.transform
        // Wall decor turns on the wall (portrait or landscape); furniture
        // turns on the floor.
        let axis: SIMD3<Float> = placed[id]?.piece.goesOnWall == true ? [0, 0, 1] : [0, 1, 0]
        transform.rotation = simd_quatf(angle: .pi / 2, axis: axis) * transform.rotation
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

    /// Dragging wall decor: it follows the finger along the wall.
    @ObservationIgnored private var sliding: UUID?

    @objc private func slid(_ gesture: UIPanGestureRecognizer) {
        guard let arView else { return }
        let point = gesture.location(in: arView)
        switch gesture.state {
        case .began:
            sliding = wallPiece(at: point)
            if let sliding { select(sliding) }
        case .changed:
            guard let id = sliding, let anchor = placed[id]?.entity.anchor, let target = wallTransform(at: point) else { return }
            anchor.transform = target
        default:
            sliding = nil
        }
    }

    /// The wall decor piece under a point on the screen, if any.
    private func wallPiece(at point: CGPoint) -> UUID? {
        guard let arView else { return nil }
        var hit = arView.entity(at: point)
        while let current = hit, !placed.values.contains(where: { $0.entity === current }) {
            hit = current.parent
        }
        guard let id = placed.first(where: { $0.value.entity === hit })?.key, placed[id]?.piece.goesOnWall == true else { return nil }
        return id
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

    private func addCutout(_ cutout: CGImage, to id: UUID) {
        cutouts[id] = cutout
        hasPhotos = true
        if let entry = placed[id], entry.entity.findEntity(named: "photo") == nil {
            if entry.piece.goesOnWall {
                Self.addWallPhoto(cutout, of: entry.piece, to: entry.entity)
            } else {
                Self.addPhoto(cutout, of: entry.piece, to: entry.entity)
            }
            applyLook()
        }
    }

    /// Fetches (or has the backend make) an AI 3D model of a catalog
    /// product. The cut-out photo shows meanwhile, and stays if this fails.
    private func makeAIModel(_ productID: String, for id: UUID) async {
        let cached = ProductModelService.cacheFile(productID).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        if !cached { showHint("Making an AI 3D model of this product…") }
        do {
            guard let data = try await ProductModelService.model(productID: productID) else { clearHint(); return }
            guard await showAIModel(data, for: id, isNew: !cached) else { return }
            if let product = (pending.first { $0.id == id } ?? placed[id]?.piece)?.product {
                SavedModels.shared.remember(product)
            }
        } catch let failure as ProductModelService.Failure {
            if failure != .notAvailable { showHint(failure.localizedDescription + " Showing the photo instead.", seconds: 4) } else { clearHint() }
        } catch {
            showHint("The 3D model couldn't be opened. Showing the photo instead.", seconds: 4)
        }
    }

    /// Opens an AI-made GLB, stands it up straight, and shows it. False if
    /// it couldn't be opened (the photo stays).
    @discardableResult
    private func showAIModel(_ data: Data, for id: UUID, isNew: Bool) async -> Bool {
        let piece = pending.first { $0.id == id } ?? placed[id]?.piece
        let isSet = piece.map { ModelFit.isSet(name: $0.name) } ?? false
        let target = piece.map { SIMD3<Float>(Float($0.widthCm / 100), Float($0.heightCm / 100), Float($0.depthCm / 100)) } ?? .one
        do {
            let (parsed, placedAsSet) = try await Task.detached {
                var model = try GLBModel(data: data)
                // Stand it up straight and square it before sizing it.
                model.standUp()
                // A set (table and chairs): the listed size is the table's,
                // so size by the table and let the chairs sit around it.
                let asSet = isSet && model.placeAsSet(target: target)
                return (model, asSet)
            }.value
            let model = try parsed.entity()
            guard models[id] == nil else { return false }
            aiModelIDs.insert(id)
            if placedAsSet { trueSizeIDs.insert(id) }
            addModel(model, to: id)
            if isNew { showHint("3D model ready. It's AI-generated, so details may differ.", seconds: 4) }
            if selected?.id == id { selected = placed[id]?.piece }
            return true
        } catch {
            showHint("The 3D model couldn't be opened. Showing the photo instead.", seconds: 4)
            return false
        }
    }

    @ObservationIgnored private var hintTask: Task<Void, Never>?
    /// A message over the camera; with `seconds`, it goes away by itself.
    private func showHint(_ text: String, seconds: Double? = nil) {
        hintTask?.cancel()
        message = text
        guard let seconds else { return }
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    private func clearHint() {
        hintTask?.cancel()
        message = nil
    }

    private func addModel(_ model: Entity, to id: UUID) {
        models[id] = model
        hasPhotos = true
        if let entry = placed[id] {
            entry.entity.findEntity(named: "photo")?.removeFromParent()
            Self.addModel(model, of: entry.piece, to: entry.entity, stretch: aiModelIDs.contains(id), asIs: trueSizeIDs.contains(id))
            applyLook()
        }
    }

    /// Shows each piece's photo, or its box shape when it has no photo
    /// (or Shape is picked).
    private func applyLook() {
        for entry in placed.values {
            let photo = entry.entity.findEntity(named: "photo")
            photo?.isEnabled = look == .photo
            entry.entity.findEntity(named: "shape")?.isEnabled = look == .shape || photo == nil
        }
    }

    /// Standing photos always face the camera, so the piece looks the same
    /// from wherever you stand (it's a flat picture, not a model).
    private func turnPhotosToCamera() {
        guard look == .photo, let arView else { return }
        let camera = arView.cameraTransform.translation
        for entry in placed.values {
            guard let photo = entry.entity.findEntity(named: "photo"), photo.components[BillboardTag.self] != nil else { continue }
            let position = photo.position(relativeTo: nil)
            let yaw = atan2(camera.x - position.x, camera.z - position.z)
            photo.setOrientation(simd_quatf(angle: yaw, axis: [0, 1, 0]), relativeTo: nil)
        }
    }

    // MARK: Aiming at the floor (or a wall, for wall decor)

    /// Where a point on the screen meets a wall, facing out of the wall
    /// toward the phone, with the piece upright.
    // MARK: Marking a wall on the floor

    func startWallMarking() {
        wallMarkStep = 0
        markStart = nil
        footprint?.isEnabled = false
    }

    func cancelWallMarking() {
        wallMarkStep = nil
        markStart = nil
        clearMarkDots(keepWalls: true)
    }

    func markWallPoint() {
        guard let point = floorAim, let step = wallMarkStep, let arView else { return }
        addMarkDot(at: point)
        if step == 0 {
            markStart = point
            wallMarkStep = 1
            return
        }
        guard let start = markStart else { return }
        var along = point - start
        along.y = 0
        guard simd_length(along) > 0.15 else { return }   // too close together to tell the direction
        var normal = simd_normalize(simd_cross(simd_normalize(along), [0, 1, 0]))
        let toCamera = arView.cameraTransform.translation - start
        if simd_dot(normal, toCamera) < 0 { normal = -normal }
        markedWalls.append((start, normal, start, point))
        hasMarkedWall = true
        showMarkedWall(from: start, to: point, normal: normal)
        wallMarkStep = nil
        markStart = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Where the aim meets the floor, while marking.
    private func updateFloorAim() {
        guard let arView, wallMarkStep != nil else { return }
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let result = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .horizontal).first
        floorAim = result.map { simd_make_float3($0.worldTransform.columns.3) }
        if floorUnderDot != (floorAim != nil) { floorUnderDot = floorAim != nil }
        if let floorAim {
            if markNodes.last?.name != "aim" {
                let ring = ModelEntity(mesh: .generatePlane(width: 0.06, depth: 0.06, cornerRadius: 0.03), materials: [UnlitMaterial(color: .white)])
                ring.name = "aim"
                markAnchor.addChild(ring)
                markNodes.append(ring)
            }
            markNodes.last?.position = floorAim
        }
    }

    private func addMarkDot(at point: SIMD3<Float>) {
        let dot = ModelEntity(mesh: .generateSphere(radius: 0.02), materials: [UnlitMaterial(color: UIColor(Theme.accent))])
        dot.position = point
        markAnchor.addChild(dot)
    }

    /// A faint see-through wall standing on the marked line, so it's clear
    /// where the art will go.
    private func showMarkedWall(from a: SIMD3<Float>, to b: SIMD3<Float>, normal: SIMD3<Float>) {
        clearMarkDots(keepWalls: true)
        let width = simd_distance(SIMD2(a.x, a.z), SIMD2(b.x, b.z)) + 1
        let height: Float = 2.4
        let wall = ModelEntity(mesh: .generatePlane(width: width, height: height), materials: [Self.seeThrough(.white, 0.12)])
        wall.name = "markedWall"
        wall.position = (a + b) / 2 + SIMD3(0, height / 2, 0)
        wall.orientation = simd_quatf(angle: atan2(normal.x, normal.z), axis: [0, 1, 0])
        markAnchor.addChild(wall)
    }

    private func clearMarkDots(keepWalls: Bool) {
        for child in Array(markAnchor.children) where !(keepWalls && child.name == "markedWall") {
            child.removeFromParent()
        }
        markNodes.removeAll()
    }

    /// Where a screen point's ray meets a marked wall (the nearest one in
    /// front, near where it was marked), facing into the room.
    private func markedWallHit(at point: CGPoint) -> Transform? {
        guard let arView, let ray = arView.ray(through: point) else { return nil }
        var best: (t: Float, wall: (point: SIMD3<Float>, normal: SIMD3<Float>, from: SIMD3<Float>, to: SIMD3<Float>))?
        for wall in markedWalls {
            let facing = simd_dot(wall.normal, ray.direction)
            guard abs(facing) > 1e-3 else { continue }
            let t = simd_dot(wall.normal, wall.point - ray.origin) / facing
            guard t > 0.1, t < 10 else { continue }
            // Stay near the marked stretch (a little past each end is fine).
            let hit = ray.origin + ray.direction * t
            let along = simd_normalize(SIMD3(wall.to.x - wall.from.x, 0, wall.to.z - wall.from.z))
            let s = simd_dot(hit - wall.from, along)
            let length = simd_distance(SIMD2(wall.from.x, wall.from.z), SIMD2(wall.to.x, wall.to.z))
            guard s > -1, s < length + 1 else { continue }
            if best == nil || t < best!.t { best = (t, wall) }
        }
        guard let best else { return nil }
        let position = ray.origin + ray.direction * best.t
        let n = best.wall.normal
        return Transform(rotation: simd_quatf(angle: atan2(n.x, n.z), axis: [0, 1, 0]), translation: position)
    }

    private func wallTransform(at point: CGPoint) -> Transform? {
        guard let arView else { return nil }
        // A wall the person marked wins: they marked it because ARKit
        // couldn't see it.
        if let marked = markedWallHit(at: point) { return marked }
        // A wall ARKit has actually found first, then its best guess.
        // (Not the endless extension of a found wall: that runs on past
        // corners, which put the outline outside the room.)
        func hit(_ p: CGPoint) -> SIMD3<Float>? {
            for target in [ARRaycastQuery.Target.existingPlaneGeometry, .estimatedPlane] {
                if let result = arView.raycast(from: p, allowing: target, alignment: .vertical).first {
                    return simd_make_float3(result.worldTransform.columns.3)
                }
            }
            return nil
        }
        guard let position = hit(point) else { return nil }
        let toCamera = arView.cameraTransform.translation - position
        // Which way the wall runs: from two more points beside the aim.
        var normal: SIMD3<Float>?
        let side: CGFloat = 40
        if let left = hit(CGPoint(x: point.x - side, y: point.y)), let right = hit(CGPoint(x: point.x + side, y: point.y)) {
            var along = right - left
            along.y = 0
            // Both points on the same wall: they're a few cm apart, level.
            if simd_length(along) > 0.01, simd_length(along) < 1.5 {
                normal = simd_normalize(simd_cross(simd_normalize(along), [0, 1, 0]))
            }
        }
        // Fallback: face the phone, level.
        if normal == nil {
            var flat = toCamera
            flat.y = 0
            guard simd_length(flat) > 1e-3 else { return nil }
            normal = simd_normalize(flat)
        }
        var n = normal!
        // The front faces the room (the phone's side).
        if simd_dot(n, toCamera) < 0 { n = -n }
        return Transform(rotation: simd_quatf(angle: atan2(n.x, n.z), axis: [0, 1, 0]), translation: position)
    }

    private func updateAim() {
        if wallMarkStep != nil {
            updateFloorAim()
            return
        }
        guard let arView, let next = pending.first else { return }
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        if next.goesOnWall {
            guard var transform = wallTransform(at: center) else {
                if floorFound { floorFound = false }
                footprint?.isEnabled = false
                let words = hasMarkedWall
                    ? "Point at the wall you marked, or at another wall."
                    : "Point at a wall. Plain walls can be hard to find: tap \"Wall not found?\" below to mark it on the floor instead."
                if hint != words { hint = words }
                return
            }
            if let current = footprint?.transform, footprint?.isEnabled == true,
               simd_distance(current.translation, transform.translation) < 0.3 {
                transform.translation = simd_mix(current.translation, transform.translation, simd_float3(repeating: 0.4))
                transform.rotation = simd_slerp(current.rotation, transform.rotation, 0.4)
            }
            footprint?.transform = transform
            footprint?.isEnabled = true
            aim = transform.matrix
            if !floorFound { floorFound = true }
            if hint != nil { hint = nil }
            return
        }
        guard let result = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .horizontal).first else {
            if floorFound { floorFound = false }
            footprint?.isEnabled = false
            let words = next.goesOnSurface ? "Point at a table, desk, or shelf." : "Point at the floor."
            if hint != words { hint = words }
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

    /// A flat outline of the next piece's true footprint, under the aiming
    /// point (on the wall, for wall decor: its width and height).
    private func showFootprint(for piece: ARPiece) {
        footprint?.removeFromParent()
        if piece.goesOnWall {
            let w = Float(piece.widthCm / 100), h = Float(piece.heightCm / 100)
            let frame = ModelEntity()
            let outline = Self.outline(width: w, depth: h, line: 0.012, color: .white)
            // The outline is drawn lying flat; stand it up against the wall.
            outline.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            outline.position.z = 0.004
            frame.addChild(outline)
            let fill = ModelEntity(mesh: .generatePlane(width: w, height: h), materials: [Self.seeThrough(.white, 0.18)])
            fill.position.z = 0.003
            frame.addChild(fill)
            frame.isEnabled = false
            footprintAnchor.addChild(frame)
            footprint = frame
            return
        }
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

    /// The art's picture on the front of its wall panel, fitted inside its
    /// width and height.
    static func addWallPhoto(_ cutout: CGImage, of piece: ARPiece, to root: Entity) {
        guard let texture = try? TextureResource.generate(from: cutout, options: .init(semantic: .color)) else { return }
        let w = Float(piece.widthCm / 100), h = Float(piece.heightCm / 100)
        let d = max(Float(piece.depthCm / 100), 0.005)
        var photoMaterial = UnlitMaterial()
        photoMaterial.color = .init(tint: .white, texture: .init(texture))
        photoMaterial.opacityThreshold = 0.5
        let aspect = Float(cutout.width) / Float(max(cutout.height, 1))
        var pw = w, ph = w / aspect
        if ph > h { ph = h; pw = h * aspect }
        let photo = ModelEntity(mesh: .generatePlane(width: pw, height: ph), materials: [photoMaterial])
        photo.name = "photo"
        photo.position.z = d + 0.002
        root.addChild(photo)
    }

    /// Wall decor: a thin panel flat on the wall, centered on where it was
    /// placed, with the photo (or cutout) on its front.
    static func makeWallEntity(for piece: ARPiece, cutout: CGImage?) -> ModelEntity {
        let w = Float(piece.widthCm / 100), h = Float(piece.heightCm / 100)
        let d = max(Float(piece.depthCm / 100), 0.005)
        let root = ModelEntity()
        let shape = Entity()
        shape.name = "shape"
        let panel = ModelEntity(mesh: .generateBox(size: [w, h, d], cornerRadius: min(d / 2, 0.003)),
                                materials: [material(for: .main, piece.colors)])
        panel.name = "main"
        panel.position.z = d / 2
        shape.addChild(panel)
        root.addChild(shape)
        if let cutout { addWallPhoto(cutout, of: piece, to: root) }
        let selection = outline(width: w + 0.04, depth: h + 0.04, line: 0.012, color: UIColor(Theme.accent))
        selection.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        selection.position.z = d + 0.004
        selection.name = "selection"
        selection.isEnabled = false
        root.addChild(selection)
        root.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: [w, h, max(d, 0.02)]).offsetBy(translation: [0, 0, max(d, 0.02) / 2])])
        return root
    }

    static func makeEntity(for piece: ARPiece) -> ModelEntity {
        let root = ModelEntity()
        let shape = Entity()
        shape.name = "shape"
        root.addChild(shape)
        for part in piece.parts {
            let mesh = MeshResource.generateBox(size: part.size, cornerRadius: part.cornerRadius)
            let child = ModelEntity(mesh: mesh, materials: [material(for: part.tone, piece.colors)])
            child.name = "\(part.tone)"
            child.position = part.center
            shape.addChild(child)
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

    /// Adds the piece's photo, sized to its true size: standing up in the
    /// middle of its footprint, or lying flat for a rug.
    static func addPhoto(_ image: CGImage, of piece: ARPiece, to root: Entity) {
        guard let texture = try? TextureResource.generate(from: image, options: .init(semantic: .color)) else { return }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        // The cut-away background is see-through.
        material.opacityThreshold = 0.5
        let photo: ModelEntity
        if piece.type == .rug {
            photo = ModelEntity(mesh: .generatePlane(width: Float(piece.widthCm / 100), depth: Float(piece.depthCm / 100)), materials: [material])
            photo.position.y = 0.006
        } else {
            let size = PhotoCutout.standingSize(imageWidth: image.width, imageHeight: image.height,
                                                widthCm: piece.widthCm, depthCm: piece.depthCm, heightCm: piece.heightCm)
            let plane = ModelEntity(mesh: .generatePlane(width: size.width, height: size.height), materials: [material])
            plane.position.y = size.height / 2
            photo = ModelEntity()
            photo.addChild(plane)
            photo.components.set(BillboardTag())
        }
        photo.name = "photo"
        root.addChild(photo)
    }

    /// Opens a USDZ model. Nil if the file can't be read.
    static func loadModel(_ data: Data) -> Entity? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("piece-\(UUID().uuidString).usdz")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? data.write(to: url)) != nil else { return nil }
        return try? Entity.load(contentsOf: url)
    }

    /// The model's own size in meters (width, height, depth), or nil if it's empty.
    static func modelSize(_ data: Data) -> simd_float3? {
        guard let model = loadModel(data) else { return nil }
        let extents = model.visualBounds(relativeTo: nil).extents
        return extents.min() > 0 ? extents : nil
    }

    /// Adds the piece's 3D model, standing on the floor in the middle of
    /// its footprint and sized to fit its saved size.
    /// `asIs`: the model is already at true size and lined up (a set placed
    /// by its table), so it's used without resizing.
    static func addModel(_ model: Entity, of piece: ARPiece, to root: Entity, stretch: Bool = false, asIs: Bool = false) {
        let copy = model.clone(recursive: true)
        if asIs {
            let holder = Entity()
            holder.name = "photo"
            holder.addChild(copy)
            root.addChild(holder)
            return
        }
        let bounds = copy.visualBounds(relativeTo: nil)
        let target: simd_float3 = [Float(piece.widthCm / 100), Float(piece.heightCm / 100), Float(piece.depthCm / 100)]
        let fit: (scale: simd_float3, turned: Bool)
        if stretch {
            // AI models: fill the catalog's measured size exactly.
            fit = ModelFit.stretch(extents: bounds.extents, target: target)
        } else {
            let even = ModelFit.fit(extents: bounds.extents, target: target)
            fit = (simd_float3(repeating: even.scale), even.turned)
        }
        // Bottom-middle of the model at the origin.
        copy.position -= [bounds.center.x, bounds.min.y, bounds.center.z]
        let sized = Entity()
        sized.addChild(copy)
        sized.scale = fit.scale
        if fit.turned { sized.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0]) }
        let holder = Entity()
        holder.name = "photo"
        holder.addChild(sized)
        root.addChild(holder)
    }

    static func paint(_ root: Entity, _ colors: FurnitureColors) {
        guard let shape = root.findEntity(named: "shape") else { return }
        for child in shape.children {
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

/// Marks a standing photo that turns to face the camera.
private struct BillboardTag: Component {}

extension ARPlaceController: UIGestureRecognizerDelegate {
    /// The wall drag only starts on a piece of wall decor, so furniture
    /// keeps its own drag and twist.
    nonisolated func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        MainActor.assumeIsolated {
            guard let arView else { return false }
            return wallPiece(at: gesture.location(in: arView)) != nil
        }
    }
}

extension ARPiece {
    /// Wall decor (posters, art, mirrors, clocks, wall shelves) is placed on
    /// a wall, not the floor.
    var goesOnWall: Bool { type.category == .wallDecor }
    /// Small decor (a monitor, a lamp, a plant) usually sits on a table or
    /// desk; it's placed on any level surface, the floor included.
    var goesOnSurface: Bool { type.category == .smallDecor }
}
