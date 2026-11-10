import SwiftUI
import Vision
import CoreImage

/// The objects the iPhone found in a photo, so the person can pick which
/// ones make up their piece. (On a desk, the iPhone may find the laptop
/// and monitor but not the desk itself.)
final class CutoutObjects: @unchecked Sendable {
    let photo: CGImage
    private let handler: VNImageRequestHandler
    private let result: VNInstanceMaskObservation?

    /// Finds the objects. Runs on the phone; slow-ish, so call off the main thread.
    init?(photo source: UIImage) {
        guard let photo = PhotoCutout.upright(source) else { return nil }
        self.photo = photo
        handler = VNImageRequestHandler(cgImage: photo, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try? handler.perform([request])
        result = request.results?.first
    }

    var all: IndexSet { result?.allInstances ?? [] }

    /// The object at a point (0...1 across and down the photo), if any.
    func object(at point: CGPoint) -> Int? {
        guard let mask = result?.instanceMask else { return nil }
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask)
        let x = min(max(Int(point.x * CGFloat(width)), 0), width - 1)
        let y = min(max(Int(point.y * CGFloat(height)), 0), height - 1)
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let label = Int(base.load(fromByteOffset: y * CVPixelBufferGetBytesPerRow(mask) + x, as: UInt8.self))
        return label == 0 ? nil : label
    }

    /// The chosen objects cut out together, on a see-through background,
    /// cropped tight. Nil if none are chosen.
    func cutout(_ chosen: IndexSet) -> CGImage? {
        guard let result, !chosen.isEmpty,
              let buffer = try? result.generateMaskedImage(ofInstances: chosen, from: handler, croppedToInstancesExtent: true) else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        return CIContext().createCGImage(image, from: image.extent)
    }

    /// The chosen objects shown over a dimmed copy of the photo, same size.
    func preview(_ chosen: IndexSet) -> CGImage? {
        guard let result, !chosen.isEmpty,
              let buffer = try? result.generateMaskedImage(ofInstances: chosen, from: handler, croppedToInstancesExtent: false) else { return nil }
        let lifted = CIImage(cvPixelBuffer: buffer)
        let dimmed = CIImage(cgImage: photo).applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.35, kCIInputSaturationKey: 0.3])
        let combined = lifted.composited(over: dimmed)
        return CIContext().createCGImage(combined, from: dimmed.extent)
    }
}

/// Pick what the piece's cutout is: tap the objects that belong to it, or
/// use the whole photo. The result is used for "See it in my room" and for
/// making an AI 3D model.
struct CutoutPickerView: View {
    let photo: UIImage
    let itemName: String
    /// PNG of the chosen cutout (or the whole photo).
    let onDone: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var objects: CutoutObjects?
    @State private var chosen: IndexSet = []
    @State private var shown: CGImage?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Space.md) {
                Text(objects?.all.isEmpty == false
                     ? "Tap the parts that belong to your \(itemName.lowercased()). Tap again to leave one out."
                     : "No objects were found in this photo. You can use the whole photo, or retake it with less around the piece.")
                    .font(Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                ZStack {
                    if isLoading {
                        ProgressView("Finding objects…")
                    } else if let image = shown ?? objects?.photo {
                        GeometryReader { geo in
                            let fitted = fit(CGSize(width: image.width, height: image.height), in: geo.size)
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .frame(width: fitted.width, height: fitted.height)
                                .contentShape(Rectangle())
                                .onTapGesture { location in
                                    tap(CGPoint(x: location.x / fitted.width, y: location.y / fitted.height))
                                }
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text("Not quite right? Clear the piece of things sitting on it and retake the photo.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: Theme.Space.sm) {
                    Button("Use whole photo") { finish(whole: true) }
                        .font(Typography.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    PrimaryButton(title: "Use selection", systemImage: "checkmark") { finish(whole: false) }
                        .disabled(chosen.isEmpty)
                        .opacity(chosen.isEmpty ? 0.6 : 1)
                }
            }
            .padding(Theme.Space.md)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Choose the cutout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.frame(minHeight: Theme.minTap)
                }
            }
        }
        .task {
            let photo = self.photo
            let found = await Task.detached { CutoutObjects(photo: photo) }.value
            objects = found
            chosen = found?.all ?? []
            await refresh()
            isLoading = false
        }
    }

    /// `point`: 0...1 across and down the photo.
    private func tap(_ point: CGPoint) {
        guard let objects, let index = objects.object(at: point) else { return }
        if chosen.contains(index) { chosen.remove(index) } else { chosen.insert(index) }
        Task { await refresh() }
    }

    private func refresh() async {
        guard let objects else { return }
        let chosen = self.chosen
        shown = await Task.detached { objects.preview(chosen) }.value
    }

    private func finish(whole: Bool) {
        guard let objects else { return }
        let image = whole ? objects.photo : objects.cutout(chosen)
        guard let image, let data = UIImage(cgImage: image).pngData() else { return }
        onDone(data)
        dismiss()
    }

    private func fit(_ size: CGSize, in box: CGSize) -> CGSize {
        let scale = min(box.width / max(size.width, 1), box.height / max(size.height, 1))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
