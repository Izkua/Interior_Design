import SwiftUI
import Vision
import CoreImage

/// What's kept in a piece's cutout: the objects the iPhone found that the
/// person tapped, plus areas they painted in, minus areas they erased.
/// (The iPhone may find a laptop and monitor on a desk but not the desk
/// itself, so painting lets the person add it.) Kept apart from the
/// screen so it can be tested.
final class CutoutMask: @unchecked Sendable {
    let photo: CGImage
    var width: Int { photo.width }
    var height: Int { photo.height }

    private let handler: VNImageRequestHandler
    private let result: VNInstanceMaskObservation?
    private let paint: CGContext
    private let erase: CGContext
    private let context = CIContext()

    /// Finds the objects. Slow-ish, so call off the main thread.
    init?(photo source: UIImage, findObjects: Bool = true) {
        guard let photo = PhotoCutout.upright(source) else { return nil }
        self.photo = photo
        handler = VNImageRequestHandler(cgImage: photo, options: [:])
        if findObjects {
            let request = VNGenerateForegroundInstanceMaskRequest()
            try? handler.perform([request])
            result = request.results?.first
        } else {
            result = nil
        }
        func layer() -> CGContext? {
            let c = CGContext(data: nil, width: photo.width, height: photo.height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            c?.setFillColor(gray: 0, alpha: 1)
            c?.fill(CGRect(x: 0, y: 0, width: photo.width, height: photo.height))
            c?.setLineCap(.round)
            c?.setLineJoin(.round)
            return c
        }
        guard let paint = layer(), let erase = layer() else { return nil }
        self.paint = paint
        self.erase = erase
    }

    /// Every object the iPhone found.
    var allObjects: IndexSet { result?.allInstances ?? [] }

    /// The object at a point (0...1 across and down the photo), if any.
    func object(at point: CGPoint) -> Int? {
        guard let mask = result?.instanceMask else { return nil }
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
        let x = min(max(Int(point.x * CGFloat(w)), 0), w - 1)
        let y = min(max(Int(point.y * CGFloat(h)), 0), h - 1)
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let label = Int(base.load(fromByteOffset: y * CVPixelBufferGetBytesPerRow(mask) + x, as: UInt8.self))
        return label == 0 ? nil : label
    }

    /// Paints (adds) or erases (removes) a stroke between two points
    /// (0...1 across and down). `brush` is a fraction of the photo's width.
    func stroke(from a: CGPoint, to b: CGPoint, brush: CGFloat, erasing: Bool) {
        // Painting over an erased spot brings it back, and the other way round.
        let (on, off) = erasing ? (erase, paint) : (paint, erase)
        let size = CGFloat(width) * brush
        func pixel(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * CGFloat(width), y: (1 - p.y) * CGFloat(height)) }
        for (layer, value) in [(on, CGFloat(1)), (off, CGFloat(0))] {
            layer.setStrokeColor(gray: value, alpha: 1)
            layer.setLineWidth(size)
            layer.move(to: pixel(a))
            layer.addLine(to: pixel(b))
            layer.strokePath()
        }
    }

    /// Clears painting and erasing.
    func resetStrokes() {
        for layer in [paint, erase] {
            layer.setFillColor(gray: 0, alpha: 1)
            layer.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// A copy of the painted and erased areas, so the preview can be drawn
    /// in the background while the person keeps painting.
    struct Strokes: @unchecked Sendable { var painted: CGImage?; var erased: CGImage? }
    func strokes() -> Strokes { Strokes(painted: paint.makeImage(), erased: erase.makeImage()) }

    /// The final mask: white where the piece is.
    private func mask(_ chosen: IndexSet, _ strokes: Strokes) -> CIImage {
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        var mask = CIImage(color: .black).cropped(to: extent)
        if let result, !chosen.isEmpty,
           let found = try? result.generateScaledMaskForImage(forInstances: chosen, from: handler) {
            mask = CIImage(cvPixelBuffer: found)
        }
        if let painted = strokes.painted {
            mask = CIImage(cgImage: painted).applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: mask])
        }
        if let erased = strokes.erased {
            let keep = CIImage(cgImage: erased).applyingFilter("CIColorInvert")
            mask = keep.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: mask])
        }
        return mask.cropped(to: extent)
    }

    private func lifted(_ chosen: IndexSet, _ strokes: Strokes) -> CIImage {
        CIImage(cgImage: photo).applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: CGRect(x: 0, y: 0, width: width, height: height)),
            kCIInputMaskImageKey: mask(chosen, strokes),
        ])
    }

    /// The kept part bright over a dimmed photo, for the screen.
    func preview(_ chosen: IndexSet, _ strokes: Strokes) -> CGImage? {
        let dimmed = CIImage(cgImage: photo).applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.35, kCIInputSaturationKey: 0.3])
        let image = lifted(chosen, strokes).composited(over: dimmed)
        return context.createCGImage(image, from: dimmed.extent)
    }

    /// The cutout on a see-through background, cropped tight. Nil if
    /// nothing is kept.
    func cutout(_ chosen: IndexSet) -> CGImage? {
        let strokes = strokes()
        guard let box = keptBounds(chosen, strokes) else { return nil }
        return context.createCGImage(lifted(chosen, strokes), from: box)
    }

    /// The smallest box around everything kept, in pixels (Core Image's
    /// bottom-up coordinates). Measured on a small copy of the mask.
    func keptBounds(_ chosen: IndexSet, _ strokes: Strokes) -> CGRect? {
        let side = 128
        let small = mask(chosen, strokes).transformed(by: CGAffineTransform(scaleX: CGFloat(side) / CGFloat(width), y: CGFloat(side) / CGFloat(height)))
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        context.render(small, toBitmap: &pixels, rowBytes: side * 4, bounds: CGRect(x: 0, y: 0, width: side, height: side),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side where pixels[(y * side + x) * 4] > 127 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let sx = CGFloat(width) / CGFloat(side), sy = CGFloat(height) / CGFloat(side)
        // Rows come out top-first; Core Image counts from the bottom.
        return CGRect(x: CGFloat(minX) * sx, y: CGFloat(side - 1 - maxY) * sy,
                      width: CGFloat(maxX - minX + 1) * sx, height: CGFloat(maxY - minY + 1) * sy)
            .insetBy(dx: -sx, dy: -sy)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

/// Pick what the piece's cutout is: tap the objects the iPhone found, paint
/// in anything it missed (like a desk under a laptop), erase what doesn't
/// belong, or use the whole photo.
struct CutoutPickerView: View {
    let photo: UIImage
    let itemName: String
    /// PNG of the chosen cutout (or the whole photo).
    let onDone: (Data) -> Void

    enum Tool: Hashable { case tap, paint, erase }

    @Environment(\.dismiss) private var dismiss
    @State private var mask: CutoutMask?
    @State private var chosen: IndexSet = []
    @State private var shown: CGImage?
    @State private var isLoading = true
    @State private var tool: Tool = .tap
    @State private var lastPoint: CGPoint?
    @State private var refreshTask: Task<Void, Never>?

    private var instructions: String {
        switch tool {
        case .tap:
            return mask?.allObjects.isEmpty == false
                ? "Tap an object to add or remove it. Missing part of your \(itemName.lowercased())? Use Paint."
                : "No objects were found. Use Paint to color over your \(itemName.lowercased())."
        case .paint: return "Color over the parts of your \(itemName.lowercased()) to keep."
        case .erase: return "Color over anything that isn't part of it."
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Space.md) {
                Picker("Tool", selection: $tool) {
                    Label("Tap", systemImage: "hand.tap").tag(Tool.tap)
                    Label("Paint", systemImage: "paintbrush").tag(Tool.paint)
                    Label("Erase", systemImage: "eraser").tag(Tool.erase)
                }
                .pickerStyle(.segmented)

                Text(instructions)
                    .font(Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                ZStack {
                    if isLoading {
                        ProgressView("Finding objects…")
                    } else if let image = shown ?? mask?.photo {
                        GeometryReader { geo in
                            let fitted = fit(CGSize(width: image.width, height: image.height), in: geo.size)
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .frame(width: fitted.width, height: fitted.height)
                                .contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                    let point = CGPoint(x: value.location.x / fitted.width, y: value.location.y / fitted.height)
                                    touch(point)
                                }.onEnded { value in
                                    let point = CGPoint(x: value.location.x / fitted.width, y: value.location.y / fitted.height)
                                    finishTouch(point, moved: abs(value.translation.width) + abs(value.translation.height) > 8)
                                })
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: Theme.Space.sm) {
                    Button("Use whole photo") { finish(whole: true) }
                        .font(Typography.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                        .disabled(isLoading)
                    PrimaryButton(title: "Use selection", systemImage: "checkmark") { finish(whole: false) }
                        .disabled(isLoading)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start over") {
                        mask?.resetStrokes()
                        chosen = mask?.allObjects ?? []
                        refresh()
                    }
                    .frame(minHeight: Theme.minTap)
                }
            }
        }
        .task {
            let photo = self.photo
            let found = await Task.detached { CutoutMask(photo: photo) }.value
            mask = found
            chosen = found?.allObjects ?? []
            if found?.allObjects.isEmpty == true { tool = .paint }
            refresh()
            isLoading = false
        }
    }

    // MARK: Touches

    private func touch(_ point: CGPoint) {
        guard tool != .tap, let mask else { return }
        mask.stroke(from: lastPoint ?? point, to: point, brush: 0.06, erasing: tool == .erase)
        lastPoint = point
        refresh()
    }

    private func finishTouch(_ point: CGPoint, moved: Bool) {
        lastPoint = nil
        guard tool == .tap, !moved, let mask, let index = mask.object(at: point) else { return }
        if chosen.contains(index) { chosen.remove(index) } else { chosen.insert(index) }
        refresh()
    }

    /// Redraws the preview; a newer request replaces an older one.
    private func refresh() {
        guard let mask else { return }
        let chosen = self.chosen
        let strokes = mask.strokes()
        refreshTask?.cancel()
        refreshTask = Task {
            let image = await Task.detached { mask.preview(chosen, strokes) }.value
            if !Task.isCancelled { shown = image }
        }
    }

    private func finish(whole: Bool) {
        let image = whole ? (mask?.photo ?? PhotoCutout.upright(photo)) : mask?.cutout(chosen)
        guard let image, let data = UIImage(cgImage: image).pngData() else { return }
        onDone(data)
        dismiss()
    }

    private func fit(_ size: CGSize, in box: CGSize) -> CGSize {
        let scale = min(box.width / max(size.width, 1), box.height / max(size.height, 1))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
