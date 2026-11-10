import SwiftUI
import UniformTypeIdentifiers

/// The 3D part of an item or product screen, top to bottom: the 3D model
/// (if there is one), the current cutout, Change cutout, then Make AI 3D
/// and Import on one line (with a note that AI uses a limited credit), and
/// See it in my room. The cutout is shown before anything is made, so a
/// bad cutout doesn't waste a credit.
struct Model3DSection: View {
    /// "Desk", or the product's name, for the cutout picker.
    let name: String
    /// The photo to cut the piece out of (nil if there's none yet).
    let photoData: Data?
    @Binding var cutoutData: Data?
    @Binding var modelData: Data?
    /// LiDAR "Scan in 3D", for your own items on Pro iPhones.
    var allowScan = false
    /// Called after a LiDAR scan with the model (for measuring the item).
    var onScanned: ((Data) -> Void)?
    /// Called when a new model is made or imported (it's saved right away).
    var onNewModel: ((Data) -> Void)?
    /// True while the room view is open: the turning preview is taken
    /// down then, because two 3D views at once left the camera black.
    var isPaused = false
    let onSeeInRoom: () -> Void

    @State private var autoCutout: CGImage?
    @State private var showPicker = false
    @State private var showImport = false
    @State private var showScan = false
    @State private var isMaking = false
    @State private var isUpdating = false
    @State private var note: String?

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                HStack {
                    SectionHeader(title: "3D model")
                    if let modelData { Tag(text: GLBModel.isGLB(modelData) ? "AI-generated" : "Added") }
                }

                if let modelData {
                    Group {
                        if isPaused {
                            Theme.surfaceAlt
                        } else {
                            ModelPreview(data: modelData)
                        }
                    }
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                        .accessibilityLabel("3D model of \(name). Drag to turn it.")
                    if GLBModel.isGLB(modelData) {
                        Text("AI-generated 3D, approximate. Drag to turn it.")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                if photoData != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current cutout")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                        ZStack {
                            Theme.surfaceAlt
                            if let image = currentCutout {
                                Image(decorative: image, scale: 1)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(Theme.Space.sm)
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    }
                    HStack(alignment: .top, spacing: Theme.Space.sm) {
                        button("Change cutout", systemImage: "scissors") { showPicker = true }
                        button(isUpdating ? "Updating…" : "Update cutout to current picture", systemImage: "arrow.triangle.2.circlepath", lines: 2) {
                            Task { await updateToCurrentPicture() }
                        }
                        .disabled(isUpdating)
                    }
                }

                HStack(alignment: .top, spacing: Theme.Space.sm) {
                    if photoData != nil {
                        VStack(spacing: 4) {
                            button(isMaking ? "Making…" : "Make AI 3D", systemImage: "wand.and.stars") {
                                Task { await makeModel() }
                            }
                            .disabled(isMaking || currentCutout == nil)
                            Text("Uses a limited AI credit")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    button("Import 3D model", systemImage: "square.and.arrow.down") { showImport = true }
                }
                if allowScan && ObjectScan.isSupported {
                    button("Scan in 3D (LiDAR)", systemImage: "cube.transparent") { showScan = true }
                }

                if let note {
                    Text(note)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if modelData != nil {
                    Button("Remove 3D model", role: .destructive) {
                        modelData = nil
                        note = nil
                    }
                    .font(Typography.subheadline)
                    .frame(minHeight: Theme.minTap)
                }

                if ARPlaceView.isAvailable {
                    PrimaryButton(title: "See it in my room", systemImage: "arkit", action: onSeeInRoom)
                        .accessibilityHint("Shows this piece at its true size in your room, through the camera")
                }
            }
        }
        .task(id: photoData) { await findAutoCutout() }
        .onChange(of: photoData) { _, _ in
            // A new photo doesn't change the cutout: keep the one shown.
            if cutoutData == nil, let shown = autoCutout, let png = UIImage(cgImage: shown).pngData() {
                cutoutData = png
            }
        }
        .fullScreenCover(isPresented: $showPicker) {
            if let photo {
                CutoutPickerView(photo: photo, itemName: name) { png in
                    cutoutData = png
                    note = "Cutout updated."
                }
            }
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.usdz]) { importModel($0) }
        .fullScreenCover(isPresented: $showScan) {
            #if !targetEnvironment(simulator)
            ObjectScanView { data in
                modelData = data
                onScanned?(data)
                onNewModel?(data)
            }
            #endif
        }
    }

    /// The person's chosen cutout, else the one the iPhone picked.
    private var currentCutout: CGImage? {
        cutoutData.flatMap { UIImage(data: $0)?.cgImage } ?? autoCutout
    }

    private var photo: UIImage? { photoData.flatMap(UIImage.init(data:)) }

    /// The iPhone's own cutout, shown until the person picks one.
    private func findAutoCutout() async {
        guard cutoutData == nil, autoCutout == nil, let photo else { return }
        // If nothing stands out, fall back to the whole photo.
        autoCutout = await PhotoCutout.cutout(from: photo) ?? PhotoCutout.upright(photo)
    }

    /// Redoes the automatic background removal on the current photo.
    private func updateToCurrentPicture() async {
        guard let photo else { return }
        isUpdating = true
        defer { isUpdating = false }
        if let cut = await PhotoCutout.cutout(from: photo), let png = UIImage(cgImage: cut).pngData() {
            cutoutData = png
            note = "Cutout updated from the current picture."
        } else if let whole = PhotoCutout.upright(photo), let png = UIImage(cgImage: whole).pngData() {
            cutoutData = png
            note = "Nothing stood out in this picture, so the whole picture is used. Use Change cutout and Paint to pick the piece."
        }
    }

    private func makeModel() async {
        guard let image = currentCutout, let png = UIImage(cgImage: image).pngData() else { return }
        isMaking = true
        defer { isMaking = false }
        note = "Making the 3D model… this takes about a minute."
        do {
            let glb = try await ProductModelService.model(fromPhoto: png)
            modelData = glb
            onNewModel?(glb)
            note = "AI-generated 3D model added. It's approximate."
        } catch {
            note = error.localizedDescription
        }
    }

    private func importModel(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), ARPlaceController.modelSize(data) != nil else {
            note = "That file couldn't be opened as a 3D model."
            return
        }
        modelData = data
        onNewModel?(data)
        note = "3D model added. It's sized to fit the sizes above."
    }

    private func button(_ title: String, systemImage: String, lines: Int = 1, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Typography.subheadline)
                .foregroundStyle(Theme.accent)
                .multilineTextAlignment(.center)
                .lineLimit(lines)
                .padding(.horizontal, 6)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}
