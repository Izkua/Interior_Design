import SwiftUI

/// Measuring from a single photo with something of known size in it.
///
/// For a card or a sheet of paper, the person taps its four corners. That
/// gives an exact map from the photo onto the surface the card sits on, so
/// sizes on that surface are right even from an angle:
/// - card standing against the front of the item: width and height;
/// - card lying flat on the floor beside it: width and depth.
/// For a door or something the person measured, two taps give a simpler
/// scale that needs a straight-on photo.
struct ReferenceMeasureView: View {
    let image: UIImage
    /// Sizes in cm (nil for one this photo can't measure), and the photo to
    /// save with the item, with the card hidden.
    let onDone: (_ width: Double?, _ depth: Double?, _ height: Double?, _ savedPhoto: UIImage) -> Void

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue

    @State private var reference: ReferenceObject = .walletCard
    @State private var placement: CardPlacement = .standing
    @State private var customLengthCm: Double = 100
    /// Taps, in the photo's own coordinates: the reference, then the item.
    @State private var taps: [CGPoint] = []
    @State private var problem: String?
    /// Pinch to zoom in on the photo (1 = whole photo), drag to move around.
    @State private var zoom: CGFloat = 1
    @State private var zoomAtStart: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panAtStart: CGSize = .zero
    /// Where the current touch began, and the point being dragged, if any.
    @State private var touchStart: CGPoint?
    @State private var dragging: Int?

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }
    private var usesCorners: Bool { reference.rectangleCm != nil }
    private var referenceTapCount: Int { usesCorners ? 4 : 2 }

    private var referenceName: String {
        switch reference {
        case .walletCard: return "card"
        case .letterPaper, .a4Paper: return "paper"
        case .doorHeight: return "door"
        case .custom: return "thing you measured"
        }
    }

    /// What this photo can measure, given how the card was placed.
    private var secondSize: MeasureDimension {
        usesCorners && placement == .flat ? .depth : .height
    }

    private var steps: [String] {
        var list: [String]
        if usesCorners {
            list = ["a corner of the \(referenceName)", "the next corner (going around)", "the next corner", "the last corner"]
        } else if reference == .doorHeight {
            list = ["the top of the door", "the bottom of the door"]
        } else {
            list = ["one end of the \(referenceName)", "the other end"]
        }
        list += ["the item's left edge", "its right edge"]
        list += secondSize == .height
            ? ["the item's top", "the floor right under it"]
            : ["the item's front edge (on the floor)", "its back edge (on the floor)"]
        return list
    }

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            HStack {
                Picker("Reference", selection: $reference) {
                    ForEach(ReferenceObject.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                Spacer()
            }
            if reference == .walletCard {
                Text("Any wallet-size card, like a gift, library, or loyalty card. Use the back, or one with nothing personal on it. The card is hidden in the saved photo.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if usesCorners {
                Picker("The card is", selection: $placement) {
                    ForEach(CardPlacement.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(placement == .standing
                     ? "Measures width and height. Stand the \(referenceName) upright against the front of the item."
                     : "Measures width and depth. Lay the \(referenceName) flat on the floor right next to the item.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if reference == .custom {
                LengthField(title: "Its length", cm: $customLengthCm, unit: unit, range: 1...1000, scale: .furniture)
            }

            Text(taps.count < steps.count ? "Tap \(steps[taps.count])" : "All set")
                .font(Typography.headline)
                .foregroundStyle(Theme.textPrimary)

            photo

            if let warning = angleWarning {
                Text(warning).font(Typography.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem {
                Text(problem).font(Typography.caption).foregroundStyle(Theme.danger)
            }

            HStack(spacing: Theme.Space.sm) {
                PrimaryButton(title: "Undo tap", style: .tinted) {
                    if !taps.isEmpty { taps.removeLast() }
                    problem = nil
                }
                PrimaryButton(title: "Use these sizes", action: finish)
                    .disabled(taps.count < steps.count)
                    .opacity(taps.count < steps.count ? 0.5 : 1)
            }
        }
        .padding(Theme.Space.md)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Measure from photo")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: reference) { _, _ in taps = [] }
        .onChange(of: placement) { _, _ in taps = [] }
    }

    private var photo: some View {
        GeometryReader { geo in
            let view = PhotoViewport(imageSize: image.size, container: geo.size, zoom: zoom, pan: pan)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: view.fitted.width, height: view.fitted.height)
                    .scaleEffect(zoom)
                    .offset(pan)
                Canvas { context, _ in drawMarks(&context, view) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(touchGesture(view), including: .all)
            .simultaneousGesture(pinchGesture(view))
            .overlay(alignment: .topLeading) { loupe(view) }
            .overlay(alignment: .bottomTrailing) { zoomButtons(view) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Photo. Pinch to zoom, tap to place a point, drag a point to move it.")
        }
    }

    // MARK: Drawing

    private func drawMarks(_ context: inout GraphicsContext, _ view: PhotoViewport) {
        let screen = { (p: CGPoint) in view.screenPoint(fromImage: p) }
        let reference = Array(taps.prefix(referenceTapCount))
        if !reference.isEmpty {
            var outline = Path()
            outline.move(to: screen(reference[0]))
            reference.dropFirst().forEach { outline.addLine(to: screen($0)) }
            if usesCorners && reference.count == 4 { outline.closeSubpath() }
            context.stroke(outline, with: .color(Theme.accent), lineWidth: 2)
        }
        let item = Array(taps.dropFirst(referenceTapCount))
        let colors: [Color] = [MeasureDimension.width.color, secondSize.color]
        for (i, p) in item.enumerated() where i % 2 == 1 {
            var line = Path()
            line.move(to: screen(item[i - 1]))
            line.addLine(to: screen(p))
            context.stroke(line, with: .color(colors[min(i / 2, 1)]), lineWidth: 2)
        }
        // Small dots with a white ring: easy to see, and they don't cover
        // the spot. The grab area around each is much bigger (see below).
        for (index, p) in taps.enumerated() {
            let color = index < referenceTapCount ? Theme.accent : colors[min((index - referenceTapCount) / 2, 1)]
            let c = screen(p)
            let dot = CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: dot.insetBy(dx: -2, dy: -2)), with: .color(.white))
            context.fill(Path(ellipseIn: dot), with: .color(index == dragging ? .yellow : color))
        }
    }

    // MARK: Touch: tap to place, drag a point to move it, drag elsewhere to pan

    @GestureState private var fingerAt: CGPoint?

    private func touchGesture(_ view: PhotoViewport) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($fingerAt) { value, state, _ in state = value.location }
            .onChanged { value in
                if touchStart == nil {
                    touchStart = value.startLocation
                    // Grab the nearest point within 22 pt (a 44 pt target).
                    dragging = view.nearestPoint(to: value.startLocation, in: taps, within: 22)
                    panAtStart = pan
                }
                if let index = dragging {
                    taps[index] = view.imagePoint(fromScreen: value.location)
                } else if zoom > 1, hypot(value.translation.width, value.translation.height) > 10 {
                    pan = view.clamped(CGSize(width: panAtStart.width + value.translation.width,
                                              height: panAtStart.height + value.translation.height))
                }
            }
            .onEnded { value in
                defer { touchStart = nil; dragging = nil; panAtStart = pan }
                guard dragging == nil else { return }
                let moved = hypot(value.translation.width, value.translation.height)
                guard moved <= 10, taps.count < steps.count, view.isOnPhoto(value.location) else { return }
                taps.append(view.imagePoint(fromScreen: value.location))
            }
    }

    private func pinchGesture(_ view: PhotoViewport) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                dragging = nil
                zoom = min(max(zoomAtStart * value.magnification, 1), 8)
                pan = PhotoViewport(imageSize: image.size, container: view.container, zoom: zoom, pan: pan).clamped(pan)
            }
            .onEnded { _ in
                zoomAtStart = zoom
                panAtStart = pan
            }
    }

    /// A magnified circle above the finger while placing or moving a
    /// point, so the finger doesn't hide the exact spot.
    @ViewBuilder
    private func loupe(_ view: PhotoViewport) -> some View {
        if let finger = fingerAt, view.isOnPhoto(finger) {
            let size: CGFloat = 110
            let magnify = zoom * 2.5
            let imagePoint = view.imagePoint(fromScreen: finger)
            // The photo drawn at the loupe's zoom, shifted so the finger's
            // spot sits in the middle of the circle.
            let full = CGSize(width: view.fitted.width * magnify, height: view.fitted.height * magnify)
            let spot = CGPoint(x: imagePoint.x * view.fitScale * magnify, y: imagePoint.y * view.fitScale * magnify)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: full.width, height: full.height)
                    .offset(x: size / 2 - spot.x, y: size / 2 - spot.y)
                    .frame(width: size, height: size, alignment: .topLeading)
                // Crosshair.
                Path { path in
                    path.move(to: CGPoint(x: size / 2, y: size / 2 - 12)); path.addLine(to: CGPoint(x: size / 2, y: size / 2 + 12))
                    path.move(to: CGPoint(x: size / 2 - 12, y: size / 2)); path.addLine(to: CGPoint(x: size / 2 + 12, y: size / 2))
                }
                .stroke(Color.yellow, lineWidth: 1.5)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(radius: 4)
            .position(x: min(max(finger.x, size / 2), view.container.width - size / 2),
                      y: finger.y - size * 0.9 < size / 2 ? finger.y + size * 0.9 : finger.y - size * 0.9)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Zoom out, zoom in, and Fit (the whole photo).
    private func zoomButtons(_ view: PhotoViewport) -> some View {
        HStack(spacing: 6) {
            zoomButton("minus.magnifyingglass", "Zoom out", view) { zoom / 2 }
            zoomButton("plus.magnifyingglass", "Zoom in", view) { zoom * 2 }
            zoomButton("arrow.up.left.and.down.right.magnifyingglass", "Fit the whole photo", view) { 1 }
        }
        .padding(8)
    }

    private func zoomButton(_ symbol: String, _ label: String, _ view: PhotoViewport, to newZoom: @escaping () -> CGFloat) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                zoom = min(max(newZoom(), 1), 8)
                pan = PhotoViewport(imageSize: image.size, container: view.container, zoom: zoom, pan: pan).clamped(pan)
                zoomAtStart = zoom
                panAtStart = pan
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Theme.minTap, height: Theme.minTap)
                .background(.black.opacity(0.55), in: Circle())
        }
        .accessibilityLabel(label)
    }

    private var planeScale: PlaneScale? {
        guard let size = reference.rectangleCm, taps.count >= 4 else { return nil }
        return PlaneScale(corners: Array(taps.prefix(4)), sizeCm: size)
    }

    private var angleWarning: String? {
        guard planeScale?.looksAngled == true else { return nil }
        return "The \(referenceName) looks quite tilted. Sizes still work, but a photo taken more straight on is usually more accurate."
    }

    private func finish() {
        let item = Array(taps.dropFirst(referenceTapCount))
        let measure: (CGPoint, CGPoint) -> Double?
        if let size = reference.rectangleCm {
            guard let scale = PlaneScale(corners: Array(taps.prefix(4)), sizeCm: size) else {
                problem = "The corners are too close together. Undo and tap the four corners of the \(referenceName)."
                return
            }
            measure = scale.length(from:to:)
        } else {
            let known = reference.lengthCm ?? customLengthCm
            guard let scale = ReferenceScale(referenceStart: taps[0], referenceEnd: taps[1], knownLengthCm: known) else {
                problem = "The two taps are too close together. Undo and try again."
                return
            }
            measure = scale.length(from:to:)
        }
        guard let width = measure(item[0], item[1]), let second = measure(item[2], item[3]) else {
            problem = "Some taps are too close together. Undo and try again, zooming in on the photo if needed."
            return
        }
        // The card is hidden in the photo that's kept; the original is not saved.
        let saved = reference == .walletCard
            ? CardBlur.hidingCard(in: image, corners: Array(taps.prefix(referenceTapCount)))
            : image
        onDone(width, secondSize == .depth ? second : nil, secondSize == .height ? second : nil, saved)
    }

}

/// How the photo sits on screen: fitted into the space, then zoomed around
/// the middle and moved by `pan`. Converts between screen points and the
/// photo's own coordinates (where taps are stored), at any zoom.
struct PhotoViewport {
    let imageSize: CGSize
    let container: CGSize
    let zoom: CGFloat
    let pan: CGSize

    /// Scale from photo points to fitted (unzoomed) screen points.
    var fitScale: CGFloat {
        min(container.width / max(imageSize.width, 1), container.height / max(imageSize.height, 1))
    }
    var fitted: CGSize { CGSize(width: imageSize.width * fitScale, height: imageSize.height * fitScale) }
    private var center: CGPoint { CGPoint(x: container.width / 2 + pan.width, y: container.height / 2 + pan.height) }

    func screenPoint(fromImage p: CGPoint) -> CGPoint {
        let s = fitScale * zoom
        return CGPoint(x: center.x + (p.x - imageSize.width / 2) * s, y: center.y + (p.y - imageSize.height / 2) * s)
    }

    func imagePoint(fromScreen p: CGPoint) -> CGPoint {
        let s = max(fitScale * zoom, 1e-6)
        let x = imageSize.width / 2 + (p.x - center.x) / s
        let y = imageSize.height / 2 + (p.y - center.y) / s
        return CGPoint(x: min(max(x, 0), imageSize.width), y: min(max(y, 0), imageSize.height))
    }

    func isOnPhoto(_ p: CGPoint) -> Bool {
        let topLeft = screenPoint(fromImage: .zero)
        let bottomRight = screenPoint(fromImage: CGPoint(x: imageSize.width, y: imageSize.height))
        return CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y).contains(p)
    }

    /// The index of the point closest to `location` on screen, if within reach.
    func nearestPoint(to location: CGPoint, in points: [CGPoint], within reach: CGFloat) -> Int? {
        points.indices
            .map { ($0, hypot(screenPoint(fromImage: points[$0]).x - location.x, screenPoint(fromImage: points[$0]).y - location.y)) }
            .filter { $0.1 <= reach }
            .min { $0.1 < $1.1 }?.0
    }

    /// A pan that keeps the zoomed photo covering the view (no dragging it away).
    func clamped(_ proposed: CGSize) -> CGSize {
        let maxX = max(fitted.width * zoom - container.width, 0) / 2
        let maxY = max(fitted.height * zoom - container.height, 0) / 2
        return CGSize(width: min(max(proposed.width, -maxX), maxX), height: min(max(proposed.height, -maxY), maxY))
    }
}

