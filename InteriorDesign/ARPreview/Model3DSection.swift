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
    let photo: UIImage?
    @Binding var cutoutData: Data?
    @Binding var modelData: Data?
    /// LiDAR "Scan in 3D", for your own items on Pro iPhones.
    var allowScan = false
    /// Called after a LiDAR scan with the model (for measuring the item).
    var onScanned: ((Data) -> Void)?
    /// Called when a new model is made or imported (products save it).
    var onNewModel: ((Data) -> Void)?
    let onSeeInRoom: () -> Void

    @State private var autoCutout: CGImage?
    @State private var showPicker = false
    @State private var showImport = false
    @State private var showScan = false
    @State private var isMaking = false
    @State private var note: String?

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                HStack {
                    SectionHeader(title: "3D model")
                    if let modelData { Tag(text: GLBModel.isGLB(modelData) ? "AI-generated" : "Added") }
                }

                if let modelData {
                    ModelPreview(data: modelData)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                        .accessibilityLabel("3D model of \(name). Drag to turn it.")
                    if GLBModel.isGLB(modelData) {
                        Text("AI-generated 3D, approximate. Drag to turn it.")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                if photo != nil {
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
                    button("Change cutout", systemImage: "scissors") { showPicker = true }
                }

                HStack(alignment: .top, spacing: Theme.Space.sm) {
                    if photo != nil {
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
        .task(id: photo) { await findAutoCutout() }
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

    private func findAutoCutout() async {
        guard cutoutData == nil, let photo else { return }
        // If nothing stands out, fall back to the whole photo.
        autoCutout = await PhotoCutout.cutout(from: photo) ?? PhotoCutout.upright(photo)
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

    private func button(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Typography.subheadline)
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}
