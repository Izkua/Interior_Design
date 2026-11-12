import SwiftUI
import PhotosUI

/// Scan a room (Beta). LiDAR iPhones use RoomPlan; every other iPhone uses
/// a few photos plus one real measurement. Either way the result is a draft
/// the person checks in the advanced builder.
struct ScanRoomView: View {
    /// Called with the finished draft.
    let onApply: (RoomDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue
    @AppStorage(SettingsKey.demoAIFeatures) private var demoMode = false

    private enum Stage { case start, measure, capture, review, lidar }

    @State private var stage: Stage = .start
    @State private var known = KnownMeasurement(kind: .firstWall, lengthCm: 400)
    @State private var photos: [Data] = []
    @State private var draft: RoomDraft?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var selection: PhotosPickerItem?
    @State private var showTrace = false

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    /// Photo scan works when the backend is switched on, or in demo mode
    /// in debug builds.
    private var photoScanAvailable: Bool {
        #if DEBUG
        if demoMode { return true }
        #endif
        return BackendConfig.roomScanEnabled
    }

    private var service: ScanService {
        #if DEBUG
        if demoMode { return DemoScanService() }
        #endif
        return BackendScanService(accessToken: { await AuthStore.shared.validAccessToken() })
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .start: start
                case .measure: measure
                case .capture: capture
                case .review: review
                case .lidar:
                    RoomPlanScanView { result in
                        if let result {
                            draft = result
                            stage = .review
                        } else {
                            errorMessage = "The scan didn't finish. Try again, moving slowly around the room."
                            stage = .start
                        }
                    }
                    .ignoresSafeArea()
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Scan room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Tag(text: "Beta") }
            }
        }
        // Full screen, so dragging around the room can't pull a sheet down.
        .fullScreenCover(isPresented: $showTrace) {
            ARRoomTraceView { result in
                draft = result
                stage = .review
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { photo in
                showCamera = false
                if let photo { add(photo) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            selection = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let photo = UIImage(data: data) {
                    add(photo)
                }
            }
        }
    }

    // MARK: Start

    private var start: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("Get a first draft of your room's outline, then fix anything that's off. Scanning is new, so always check the result.")
                    .font(Typography.body)
                    .foregroundStyle(Theme.textSecondary)

                if RoomPlanScan.isAvailable {
                    PrimaryButton(title: "Scan with LiDAR", systemImage: "camera.metering.matrix") { stage = .lidar }
                    Text("Your iPhone can measure the room directly. Walk slowly around the edges.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                if ARMeasure.isAvailable {
                    PrimaryButton(title: "Trace room with AR", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                  style: RoomPlanScan.isAvailable ? .tinted : .filled) { showTrace = true }
                    Text("Point at each corner where a wall meets the floor, going around the room. Works on any iPhone; about 1–2 in per wall in good light.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if photoScanAvailable {
                    PrimaryButton(title: "Scan with photos", systemImage: "photo.stack", style: RoomPlanScan.isAvailable ? .tinted : .filled) {
                        stage = .measure
                    }
                    #if DEBUG
                    if demoMode {
                        Text("Demo mode: results are made up (Profile → Developer).")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.danger)
                    }
                    #endif
                } else if !RoomPlanScan.isAvailable && !ARMeasure.isAvailable {
                    AppCard {
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Label("Scanning needs a LiDAR iPhone for now", systemImage: "clock")
                                .font(Typography.headline)
                            Text("On iPhones with LiDAR (Pro models), the camera can measure the room for you. Scanning with ordinary photos is coming in a later update.")
                                .font(Typography.body)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("For now, draw your room: pick Basic for a rectangle, or Advanced to tap in corners and type each wall's length. It takes a minute or two with a tape measure.")
                                .font(Typography.body)
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            PrimaryButton(title: "Draw my room", systemImage: "pencil.and.ruler") { dismiss() }
                            #if DEBUG
                            Button("Try the demo (debug builds only)") { demoMode = true }
                                .font(Typography.subheadline)
                                .frame(minHeight: Theme.minTap)
                            #endif
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).font(Typography.caption).foregroundStyle(Theme.danger)
                }
            }
            .padding(Theme.Space.md)
        }
    }

    // MARK: One real measurement first

    private var measure: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                AppCard {
                    VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                        SectionHeader(title: "One real measurement")
                        Text("Photos can't tell a small room from a big one. Measure one wall with a tape measure; your first photo will face that wall.")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        LengthField(title: "Length of that wall", cm: $known.lengthCm, unit: unit, range: 100...3000)
                    }
                }
                PrimaryButton(title: "Start taking photos") {
                    known.kind = .firstWall
                    stage = .capture
                }
                Button("No tape measure? Use a standard door instead") {
                    known = .standardDoor
                    stage = .capture
                }
                .font(Typography.subheadline)
                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
            }
            .padding(Theme.Space.md)
        }
    }

    // MARK: The photo loop

    private var capture: some View {
        let hint = ScanLoop.nextHint(draft: draft, photoCount: photos.count)
        return ScrollView {
            VStack(spacing: Theme.Space.md) {
                Text("Photo \(min(photos.count + 1, ScanLoop.maxPhotos)) of up to \(ScanLoop.maxPhotos)")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)

                AppCard {
                    HStack(spacing: Theme.Space.md) {
                        Image(systemName: symbol(for: hint.direction))
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 64, height: 64)
                            .background(Theme.accent.opacity(0.12), in: Circle())
                            .accessibilityHidden(true)
                        Text(hint.text)
                            .font(Typography.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let draft {
                    DraftPreview(draft: draft, unit: unit)
                        .frame(height: 220)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }

                if isWorking {
                    ProgressView("Updating the outline…")
                } else {
                    if UIImagePickerController.isSourceTypeAvailable(.camera), CameraAccess.state != .denied {
                        PrimaryButton(title: "Take photo", systemImage: "camera") {
                            Task {
                                if CameraAccess.state == .notAsked { _ = await CameraAccess.request() }
                                if CameraAccess.state == .allowed { showCamera = true }
                            }
                        }
                    }
                    PhotosPicker(selection: $selection, matching: .images) {
                        Label("Choose a photo", systemImage: "photo")
                            .font(Typography.headline)
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    }
                    HStack {
                        Button("Retake last") { retakeLast() }
                            .disabled(photos.isEmpty)
                        Spacer()
                        Button("Finish now") { stage = .review }
                            .disabled(draft == nil)
                    }
                    .font(Typography.subheadline)
                    .frame(minHeight: Theme.minTap)
                }

                if let errorMessage {
                    Text(errorMessage).font(Typography.caption).foregroundStyle(Theme.danger)
                }
            }
            .padding(Theme.Space.md)
        }
    }

    private func add(_ photo: UIImage) {
        guard let data = ScanLoop.prepare(photo) else { return }
        photos.append(data)
        refresh()
    }

    /// Drops the last photo and rebuilds the draft from the rest.
    private func retakeLast() {
        guard !photos.isEmpty else { return }
        photos.removeLast()
        if photos.isEmpty {
            draft = nil
        } else {
            refresh()
        }
    }

    /// Sends all photos so far and updates the draft. A failure keeps the
    /// photos and the previous draft.
    private func refresh() {
        isWorking = true
        errorMessage = nil
        let photos = self.photos, known = self.known, previous = draft, service = self.service
        Task {
            do {
                draft = try await service.update(photos: photos, known: known, previous: previous)
                if ScanLoop.isFinished(draft: draft, photoCount: photos.count) {
                    stage = .review
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Try again."
            }
            isWorking = false
        }
    }

    // MARK: Review

    @State private var straightenCorners = true
    /// Add the furniture a LiDAR scan found to the room.
    @State private var addFurniture = true

    private var review: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                if let original = draft {
                    let straight = RoomStraightener.straightened(original)
                    let shaped = straightenCorners ? (straight ?? original) : original
                    let draft = addFurniture ? shaped : shaped.withoutFurniture
                    DraftPreview(draft: draft, unit: unit, before: straightenCorners && straight != nil ? original.corners : nil)
                        .frame(height: 300)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    let unsure = draft.uncertainWalls.count
                    Text(unsure == 0
                         ? "Here's your draft. Check the lengths with a tape measure if you can."
                         : "Here's your draft. \(unsure) \(unsure == 1 ? "wall is" : "walls are") dashed red because the scan wasn't sure. Tap them in the builder to type the real length.")
                        .font(Typography.body)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if straight != nil {
                        Toggle(isOn: $straightenCorners) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Straighten corners")
                                    .font(Typography.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(straightenCorners
                                     ? "Walls that were nearly square are now exactly 90° (or 45°). The faint line is how it was scanned."
                                     : "Showing the outline exactly as scanned.")
                                    .font(Typography.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(Theme.accent)
                    }
                    if !original.furniture.isEmpty {
                        Toggle(isOn: $addFurniture) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add the furniture it found")
                                    .font(Typography.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(addFurniture
                                     ? "Found \(ScannedFurniture.summary(original.furniture)), placed where they stand. They're added to Current Items with estimated sizes for you to check. Turn this off if you've already added them."
                                     : "Only the walls, doors and windows will be used.")
                                    .font(Typography.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(Theme.accent)
                    }
                    PrimaryButton(title: draft.furniture.isEmpty ? "Use this outline" : "Use this room", systemImage: "checkmark") {
                        onApply(draft)
                        dismiss()
                    }
                    Text(draft.furniture.isEmpty
                         ? "This replaces the room's current outline. You can undo it in the builder."
                         : "This replaces the room's current outline. Undo in the builder brings back the old outline; remove furniture you don't want from Current Items.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Theme.Space.md)
        }
    }

    private func symbol(for direction: RoomDraft.Direction) -> String {
        switch direction {
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        case .behind: return "arrow.uturn.down"
        case .ahead: return "arrow.up"
        case .up: return "arrow.up.to.line"
        case .down: return "arrow.down.to.line"
        case .done: return "checkmark"
        }
    }
}

/// A draft outline drawn like the builder's plan, with unsure walls dashed.
struct DraftPreview: View {
    let draft: RoomDraft
    let unit: UnitSystem
    /// The outline before straightening, drawn faintly behind it.
    var before: [Point2D]? = nil

    var body: some View {
        Canvas { context, size in
            let space = CanvasSpace(corners: draft.corners + (before ?? []), size: size, padding: 40)
            if let before, before.count >= 3 {
                var path = Path()
                path.addLines(before.map { space.viewPoint($0) })
                path.closeSubpath()
                context.stroke(path, with: .color(Theme.textSecondary.opacity(0.6)), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
            RoomPlanPainter.paint(&context, corners: draft.corners, features: draft.features, selectedID: nil, space: space, unit: unit)
            AdvancedPlanPainter.paintEditing(&context, corners: draft.corners, selectedWall: nil, activeCorner: nil, uncertainWalls: draft.uncertainWalls, space: space)
            // Furniture the scan found, as simple boxes.
            for piece in draft.furniture {
                let size = piece.footprint
                let topLeft = space.viewPoint(Point2D(x: piece.x - size.width / 2, y: piece.y - size.depth / 2))
                let bottomRight = space.viewPoint(Point2D(x: piece.x + size.width / 2, y: piece.y + size.depth / 2))
                let box = CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
                let shape = Path(roundedRect: box, cornerRadius: 3)
                context.fill(shape, with: .color(Theme.accent.opacity(0.18)))
                context.stroke(shape, with: .color(Theme.accent), lineWidth: 1.5)
            }
        }
        .accessibilityLabel(draft.furniture.isEmpty
                            ? "Draft outline with \(draft.corners.count) corners"
                            : "Draft outline with \(draft.corners.count) corners and \(draft.furniture.count) pieces of furniture")
    }
}
