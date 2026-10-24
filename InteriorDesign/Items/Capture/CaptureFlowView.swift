import SwiftUI
import SwiftData
import PhotosUI

/// Add an item from a photo: take or choose a photo, let the phone guess
/// what it is, pick how to size it, then check everything on the confirm
/// screen. Sizes from a photo stay "Estimated" until the person confirms.
struct CaptureFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Room.updatedAt, order: .reverse) private var rooms: [Room]

    private enum Step: Hashable { case size, reference, confirm }


    @State private var path: [Step] = []
    @State private var image: UIImage?
    @State private var label: ItemLabel?
    @State private var isLabeling = false
    @State private var draft = ItemDraft()
    @State private var method: CaptureSizeMethod = .typical
    @State private var cameraState = CameraAccess.state
    @State private var showCamera = false
    @State private var showAR = false
    @State private var photoSelection: PhotosPickerItem?

    var labeler: LabelingService = PreferredLabelingService()

    var body: some View {
        NavigationStack(path: $path) {
            pickPhoto
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .size: sizeChoice
                    case .reference:
                        if let image {
                            ReferenceMeasureView(image: image) { width, height in
                                draft.widthCm = width.rounded()
                                draft.heightCm = height.rounded()
                                method = .reference
                                // Swap the measuring screen for the confirm screen.
                                path = [.size, .confirm]
                            }
                        }
                    case .confirm: confirm
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { photo in
                showCamera = false
                if let photo { use(photo) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showAR) {
            ARMeasureView(start: (draft.widthCm, draft.depthCm, draft.heightCm)) { w, d, h in
                draft.widthCm = w.rounded()
                draft.depthCm = d.rounded()
                draft.heightCm = h.rounded()
                method = .ar
                path.append(.confirm)
            }
        }
        .onChange(of: photoSelection) { _, selection in
            guard let selection else { return }
            Task {
                if let data = try? await selection.loadTransferable(type: Data.self), let photo = UIImage(data: data) {
                    use(photo)
                }
            }
        }
    }

    // MARK: 1. Photo

    private var pickPhoto: some View {
        ScrollView {
            VStack(spacing: Theme.Space.md) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 80, height: 80)
                    .background(Theme.accent.opacity(0.12), in: Circle())
                Text("Take a photo of one piece of furniture, straight on, with the whole piece in view.")
                    .font(Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                switch cameraState {
                case .allowed, .notAsked:
                    PrimaryButton(title: "Take photo", systemImage: "camera", action: openCamera)
                case .denied:
                    AppCard {
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Label("Camera access is off", systemImage: "camera.badge.ellipsis")
                                .font(Typography.headline)
                            Text("To take photos here, allow camera access in Settings. You can still choose a photo from your library.")
                                .font(Typography.caption)
                                .foregroundStyle(Theme.textSecondary)
                            PrimaryButton(title: "Open Settings", style: .tinted) { CameraAccess.openSettings() }
                        }
                    }
                case .unavailable:
                    Text("This device has no camera, so choose a photo instead.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                PhotosPicker(selection: $photoSelection, matching: .images) {
                    Label("Choose from library", systemImage: "photo.on.rectangle")
                        .font(Typography.headline)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                }

                if isLabeling {
                    ProgressView("Looking at your photo…")
                }
            }
            .padding(Theme.Space.md)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Add from photo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openCamera() {
        Task {
            if cameraState == .notAsked {
                cameraState = await CameraAccess.request() ? .allowed : .denied
            }
            if cameraState == .allowed { showCamera = true }
        }
    }

    /// Labels the photo on the phone, then moves on to sizing.
    private func use(_ photo: UIImage) {
        image = photo
        isLabeling = true
        Task {
            let result = try? await labeler.label(photo)
            label = result
            var fresh = ItemDraft(type: result?.type ?? .other, room: rooms.first)
            fresh.photoData = PhotoResizer.jpeg(from: photo.jpegData(compressionQuality: 0.9) ?? Data())
            draft = fresh
            method = .typical
            isLabeling = false
            path = [.size]
        }
    }

    // MARK: 2. How to size it

    private var sizeChoice: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                Text(label?.confidenceNote ?? "We couldn't tell what this is. You can pick the type on the next screen.")
                    .font(Typography.body)
                    .foregroundStyle(Theme.textPrimary)

                SectionHeader(title: "How should we size it?")
                if ARMeasure.isAvailable {
                    option("Measure with the camera", "Point at each end in AR. Most accurate.", "ruler") {
                        showAR = true
                    }
                }
                option("Use something in the photo", "Tap a credit card, paper, or door in the photo, then the furniture.", "creditcard") {
                    path.append(.reference)
                }
                option("Use a typical size", label == nil ? "Start from a typical size and adjust it." : "Start from the usual size for a \(draft.type.displayName.lowercased()) and adjust it.", "square.dashed") {
                    method = .typical
                    path.append(.confirm)
                }
            }
            .padding(Theme.Space.md)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Size")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func option(_ title: String, _ detail: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            AppCard {
                HStack(spacing: Theme.Space.md) {
                    Image(systemName: symbol)
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                        .background(Theme.accent.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Typography.headline).foregroundStyle(Theme.textPrimary)
                        Text(detail).font(Typography.caption).foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: 3. Confirm

    private var confirm: some View {
        // Bindings, not plain values: screens pushed on a navigation stack
        // can otherwise keep showing the values from when they were built.
        CaptureConfirmView(draft: $draft, label: $label, method: $method, rooms: rooms) { confirmed in
            let item = draft.makeItem()
            item.isEstimated = !confirmed
            context.insert(item)
            try? context.save()
            dismiss()
        }
    }

}

/// How a captured item's size was found, for the confidence note.
enum CaptureSizeMethod {
    case typical, reference, ar

    var note: String {
        switch self {
        case .ar: return "Measured in AR. Usually close, but check edges that were hard to aim at."
        case .reference: return "Worked out from the reference in your photo. This can be off by 10% or more if the reference wasn't right next to the furniture. Depth can't be seen in one photo, so it's the usual depth for this type."
        case .typical: return "These are typical sizes for this type, not your piece. Measure it if you can."
        }
    }
}

/// The last step: the photo, the guessed type, and every size, all
/// editable. Shows "Estimated" until the person confirms.
struct CaptureConfirmView: View {
    @Binding var draft: ItemDraft
    @Binding var label: ItemLabel?
    @Binding var method: CaptureSizeMethod
    let rooms: [Room]
    /// true when the person confirms the sizes, false to keep them estimated.
    let onSave: (_ confirmed: Bool) -> Void

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue
    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                if let data = draft.photoData, let photo = UIImage(data: data) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }

                AppCard {
                    VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                        HStack {
                            SectionHeader(title: "What is it?")
                            if let label {
                                Tag(text: "\(Int((label.confidence * 100).rounded()))% sure")
                            }
                        }
                        FlowLayout(spacing: Theme.Space.sm) {
                            ForEach(ItemType.allCases) { type in
                                Chip(title: type.displayName, systemImage: type.symbol, isSelected: draft.type == type) {
                                    draft.setType(type)
                                }
                            }
                        }
                        TextField(draft.type.displayName, text: $draft.name)
                            .font(Typography.headline)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 48)
                            .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                        HStack {
                            SectionHeader(title: "Size")
                            Tag(text: "Estimated")
                        }
                        HStack(alignment: .top, spacing: Theme.Space.sm) {
                            LengthField(title: "Width", cm: $draft.widthCm, unit: unit, range: 0.5...1000, scale: .furniture)
                            LengthField(title: "Depth", cm: $draft.depthCm, unit: unit, range: 0.5...1000, scale: .furniture)
                            LengthField(title: "Height", cm: $draft.heightCm, unit: unit, range: 0.5...1000, scale: .furniture)
                        }
                        Text(method.note)
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                AppCard {
                    RoomChooser(rooms: $draft.rooms, anyRoom: $draft.anyRoom, allRooms: rooms)
                }

                PrimaryButton(title: "Sizes are right, save", systemImage: "checkmark") { onSave(true) }
                Button("Save as estimate, I'll measure later") { onSave(false) }
                    .font(Typography.subheadline)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTap)
            }
            .padding(Theme.Space.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Check and save")
        .navigationBarTitleDisplayMode(.inline)
    }
}
