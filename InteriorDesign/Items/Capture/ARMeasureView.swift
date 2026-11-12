import SwiftUI
import ARKit
import SceneKit
import simd

/// Measuring with the camera in AR. Works on any iPhone with ARKit world
/// tracking (no LiDAR needed): ARKit finds surfaces as you move the phone,
/// and points are placed where the aiming dot meets them.
///
/// Only offered when `ARMeasure.isAvailable`, so it never shows in the
/// Simulator.
enum ARMeasure {
    static var isAvailable: Bool { ARWorldTrackingConfiguration.isSupported }

    /// Below this (the sine of about 12°), a ray is too close to running
    /// along a plane to place a point on it reliably.
    static let minGrazing: Float = 0.2

    /// Straight-line distance between two points in the room, in cm.
    /// (ARKit works in meters.)
    static func distanceCm(_ a: simd_float3, _ b: simd_float3) -> Double {
        Double(simd_distance(a, b)) * 100
    }

    /// Where a ray (from the camera through the aiming dot) meets a flat
    /// plane, or nil if it points away from it or runs alongside it.
    static func intersect(origin: simd_float3, direction: simd_float3,
                          planePoint: simd_float3, normal: simd_float3) -> simd_float3? {
        let facing = simd_dot(normal, direction)
        guard abs(facing) > 1e-4 else { return nil }
        let t = simd_dot(normal, planePoint - origin) / facing
        guard t > 0.05, t < 10 else { return nil }
        return origin + direction * t
    }

    /// The guide plane for the end point, through the start point.
    /// Width and depth: the flat plane the start is on (usually the floor),
    /// so aiming anywhere along the item gives a point at the same height.
    /// Height: a standing plane facing the camera, so aiming straight up
    /// from the start measures height.
    static func guidePlane(for step: Int, start: simd_float3, cameraPosition: simd_float3) -> (point: simd_float3, normal: simd_float3) {
        if step == 2 {
            var toCamera = cameraPosition - start
            toCamera.y = 0
            let length = simd_length(toCamera)
            return (start, length > 1e-3 ? toCamera / length : simd_float3(0, 0, 1))
        }
        return (start, simd_float3(0, 1, 0))
    }

    /// The point on a standing line (straight up from `base`) closest to a
    /// ray. Used for height: aim at the top of the item and the height is
    /// read off the line rising from the floor point.
    static func pointOnVerticalLine(base: simd_float3, origin: simd_float3, direction: simd_float3) -> simd_float3? {
        // Closest points between the line base + s·up and the ray origin + t·direction.
        let up = simd_float3(0, 1, 0)
        let w = base - origin
        let b = simd_dot(up, direction)
        let denominator = 1 - b * b
        guard denominator > 1e-4 else { return nil }   // aiming straight up or down
        let d = simd_dot(up, w), e = simd_dot(direction, w)
        let s = (b * e - d) / denominator
        let t = (e - b * d) / denominator
        guard t > 0.05 else { return nil }             // behind the camera
        return base + up * max(s, 0)
    }

    /// The middle reading of recent frames, axis by axis. One shaky frame
    /// can't pull a tapped point off, which a plain average would allow.
    static func median(_ points: [simd_float3]) -> simd_float3? {
        guard !points.isEmpty else { return nil }
        func mid(_ values: [Float]) -> Float {
            let sorted = values.sorted()
            let n = sorted.count
            return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
        }
        return simd_float3(mid(points.map(\.x)), mid(points.map(\.y)), mid(points.map(\.z)))
    }

    /// Moves a shown value part of the way toward a new reading, so small
    /// jitter doesn't make the number jump around.
    static func smooth(_ old: simd_float3?, toward new: simd_float3, amount: Float = 0.35) -> simd_float3 {
        guard let old else { return new }
        return old + (new - old) * amount
    }

    /// The feature point (a speck ARKit tracks on any textured surface, like
    /// fabric) closest to the aiming ray, within a small angle. Used when
    /// ARKit hasn't found a flat surface there.
    static func nearestFeaturePoint(_ points: [simd_float3], origin: simd_float3, direction: simd_float3,
                                    maxAngleDegrees: Float = 2.5) -> simd_float3? {
        let limit = cos(maxAngleDegrees * .pi / 180)
        var best: (point: simd_float3, cosine: Float)?
        for point in points {
            let offset = point - origin
            let distance = simd_length(offset)
            guard distance > 0.15, distance < 6 else { continue }
            let cosine = simd_dot(offset / distance, direction)
            if cosine >= limit, cosine > (best?.cosine ?? -1) {
                best = (point, cosine)
            }
        }
        return best?.point
    }
}

/// One of the three sizes, with the color and words used for it everywhere
/// on the measuring screen, so it's always clear which one you're on.
enum MeasureDimension: Int, CaseIterable, Identifiable {
    case width, depth, height
    var id: Int { rawValue }

    var name: String { ["width", "depth", "height"][rawValue] }
    var title: String { name.uppercased() }
    var short: String { ["W", "D", "H"][rawValue] }
    var color: Color { [Color.blue, Color.orange, Color.green][rawValue] }
    var uiColor: UIColor { [UIColor.systemBlue, .systemOrange, .systemGreen][rawValue] }
    /// One plain line on what to measure.
    var explanation: String {
        switch self {
        case .width: return "Width: from the left edge to the right edge of the top."
        case .depth: return "Depth: from the front edge to the back edge of the top."
        case .height: return "Height: from the floor to the highest point."
        }
    }
}

/// Width, depth, and height, measured in any order: each needs a start
/// point and an end point. Kept apart from the screen so it can be tested.
struct MeasureSteps: Equatable {
    static let names = MeasureDimension.allCases.map(\.name)

    /// Each size in cm, once measured.
    private(set) var values: [Double?] = [nil, nil, nil]
    /// A size picked to measure again; otherwise the first one not done yet.
    private(set) var chosen: MeasureDimension?
    /// True between "Set start" and "Set end".
    private(set) var hasStart = false
    /// Order sizes were measured in, for Back.
    private var history: [MeasureDimension] = []

    /// Height first: its top gives a level plane at the item's top, and
    /// width and depth are then measured on that plane, right on the item.
    static let order: [MeasureDimension] = [.height, .width, .depth]

    var current: MeasureDimension? {
        chosen ?? Self.order.first { values[$0.rawValue] == nil }
    }
    var isDone: Bool { current == nil }
    var currentName: String? { current?.name }
    /// Finished measurements, in cm, in width-depth-height order.
    var results: [Double] { values.compactMap { $0 } }
    /// "Step 2 of 3".
    var stepNumber: Int { (current.flatMap { Self.order.firstIndex(of: $0) } ?? 2) + 1 }

    func value(_ dimension: MeasureDimension) -> Double? { values[dimension.rawValue] }

    mutating func setStart() { hasStart = !isDone }

    /// Records a finished measurement. Very short ones (under 1 cm) are
    /// almost always a double tap, so they're ignored and the person tries
    /// that end again.
    @discardableResult
    mutating func setEnd(distanceCm: Double) -> Bool {
        guard hasStart, let current, distanceCm >= 1 else { return false }
        values[current.rawValue] = distanceCm
        history.removeAll { $0 == current }
        history.append(current)
        chosen = nil
        hasStart = false
        return true
    }

    /// Measure this size again.
    mutating func remeasure(_ dimension: MeasureDimension) {
        chosen = dimension
        hasStart = false
    }

    /// Goes back one step: forgets a start point, or the last measurement.
    mutating func undo() {
        if hasStart {
            hasStart = false
        } else if let last = history.popLast() {
            values[last.rawValue] = nil
            chosen = nil
        }
    }

    /// Furniture is almost always wider than deep, so this usually means
    /// the two were measured the wrong way round.
    var looksSwapped: Bool {
        guard let w = value(.width), let d = value(.depth) else { return false }
        return w < d * 0.9
    }

    /// Fills in the current size without measuring it (for example, a
    /// monitor's depth, which is hard to aim at).
    mutating func skip(using cm: Double) {
        guard let current, cm > 0 else { return }
        values[current.rawValue] = cm
        history.removeAll { $0 == current }
        history.append(current)
        chosen = nil
        hasStart = false
    }

    mutating func swapWidthAndDepth() {
        values.swapAt(0, 1)
    }
}

/// Measure width, depth, and height one after another: aim the dot at one
/// end, tap "Set start", aim at the other end, tap "Set end".
struct ARMeasureView: View {
    /// Starting values (the type's usual size), in cm.
    let start: (width: Double, depth: Double, height: Double)
    let onDone: (_ width: Double, _ depth: Double, _ height: Double) -> Void
    /// "Type the sizes instead": close the camera and go to typing.
    var onTypeInstead: (() -> Void)? = nil
    /// Decor that stands on a desk or table (a monitor, a lamp): measured
    /// from that surface, and its depth can be skipped.
    var onSurface = false

    @Environment(\.dismiss) private var dismiss
    @State private var steps = MeasureSteps()
    @State private var model = ARMeasureModel()
    @State private var tapCount = 0
    /// Measure width and depth across the item's top (default) or along
    /// the floor at its base (handy for rugs, or a sofa with a clear base).
    @State private var measureAtTop = true

    private var unit: UnitSystem { UnitSystem.deviceDefault }

    var body: some View {
        ZStack {
            ARViewContainer(model: model)
                .ignoresSafeArea()

            // The aiming dot, in the color of the size being measured.
            Circle()
                .stroke(.white, lineWidth: 2)
                .background(Circle().fill((model.surfaceUnderDot ? (steps.current?.color ?? Theme.accent) : Color.gray).opacity(0.8)))
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(spacing: Theme.Space.sm) {
                header
                progressChips
                if let current = steps.current, current != .height, model.topY != nil {
                    Picker("Measure at", selection: $measureAtTop) {
                        Text("Top of item").tag(true)
                        Text(onSurface ? "Desk or table" : "Floor").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.Space.md)
                    .accessibilityLabel("Measure width and depth at the top of the item or on the floor")
                }
                if let warning = sizeWarning {
                    Text(warning)
                        .font(Typography.subheadline)
                        .foregroundStyle(.yellow)
                        .padding(8)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                        .padding(.horizontal, Theme.Space.md)
                }
                Spacer()
                if steps.hasStart, let live = model.liveDistanceCm, let current = steps.current {
                    Text("\(current.short) \(Length.formatFurniture(live, system: unit))")
                        .font(Typography.title)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(current.color.opacity(0.9), in: Capsule())
                        .accessibilityLabel("\(current.name) so far, \(Length.formatFurniture(live, system: unit))")
                }
                if onSurface, steps.current == .depth, !steps.hasStart {
                    Button("Skip depth (use \(Length.formatFurniture(typical(.depth), system: unit)))") {
                        steps.skip(using: typical(.depth))
                        model.clearStart()
                        model.syncLines(steps)
                    }
                    .font(Typography.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Theme.minTap)
                    .background(MeasureDimension.depth.color.opacity(0.8), in: Capsule())
                    .accessibilityHint("Thin things like monitors are hard to measure front to back. You can change it after.")
                }
                Button("Type the sizes instead") {
                    dismiss()
                    onTypeInstead?()
                }
                .font(Typography.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: Theme.minTap)
                .background(.black.opacity(0.6), in: Capsule())
                .accessibilityHint("Closes the camera. You can type the sizes on the next screen.")

                HStack(spacing: Theme.Space.sm) {
                    PrimaryButton(title: steps.hasStart || !steps.results.isEmpty ? "Back" : "Cancel", style: .tinted) {
                        if steps.hasStart {
                            steps.undo()
                            model.clearStart()
                        } else if !steps.results.isEmpty {
                            steps.undo()
                            model.syncLines(steps)
                        } else {
                            dismiss()
                        }
                    }
                    PrimaryButton(title: steps.hasStart ? "Set end" : "Set start", action: setPoint)
                        .disabled(!model.surfaceUnderDot || steps.isDone)
                        .opacity(model.surfaceUnderDot ? 1 : 0.5)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.md)
            }

            if steps.isDone {
                reviewCard
            }
        }
        .sensoryFeedback(.impact, trigger: tapCount)
        .onChange(of: steps.current) { _, next in
            guard let next else { return }
            UIAccessibility.post(notification: .announcement, argument: "Step \(steps.stepNumber) of 3. Measure the \(next.name).")
        }
        .onAppear {
            // Thin, upright things have no top to aim across: measure on
            // the desk or table they stand on instead.
            if onSurface { measureAtTop = false }
            model.currentColor = steps.current?.uiColor ?? .systemBlue
            model.upcoming = steps.current
            model.measureAtTop = measureAtTop
        }
        .onChange(of: steps.current) { _, next in
            model.currentColor = next?.uiColor ?? .systemBlue
            model.upcoming = next
        }
        .onChange(of: measureAtTop) { _, value in model.measureAtTop = value }
        .onDisappear { model.pause() }
    }

    // MARK: Header: which size, a picture of it, what to do

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let current = steps.current {
                HStack(spacing: Theme.Space.sm) {
                    MeasureDiagram(highlight: current)
                        .frame(width: 70, height: 50)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Step \(steps.stepNumber) of 3")
                            .font(Typography.caption)
                            .foregroundStyle(.white.opacity(0.85))
                        Text(current.title)
                            .font(.system(.title, design: .rounded, weight: .heavy))
                            .foregroundStyle(current.color)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(steps.stepNumber) of 3: \(current.name)")
                Text(onSurface && current == .height ? "Height: from the desk or table it stands on to its highest point." : current.explanation)
                    .font(Typography.subheadline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(instruction)
                .font(Typography.headline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let hint = model.hint {
                Text(hint)
                    .font(Typography.subheadline)
                    .foregroundStyle(.yellow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .padding(.top, Theme.Space.sm)
        .padding(.horizontal, Theme.Space.md)
    }

    /// Width ✓ 82″ · Depth … · Height …  Tap one to measure it again.
    private var progressChips: some View {
        HStack(spacing: 6) {
            ForEach(MeasureSteps.order) { dimension in
                let value = steps.value(dimension)
                let isCurrent = steps.current == dimension
                Button {
                    steps.remeasure(dimension)
                    model.clearStart()
                } label: {
                    Text(value.map { "\(dimension.short) \(Length.formatFurniture($0, system: unit))" } ?? "\(dimension.name.capitalized) …")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .background(dimension.color.opacity(isCurrent ? 0.95 : (value == nil ? 0.3 : 0.6)), in: Capsule())
                        .overlay(Capsule().stroke(.white, lineWidth: isCurrent ? 2 : 0))
                }
                .accessibilityLabel(value.map { "\(dimension.name) \(Length.formatFurniture($0, system: unit)). Double-tap to measure again." } ?? "\(dimension.name), not measured yet")
            }
        }
    }

    /// The usual size of this type, for the "too big" check.
    private func typical(_ dimension: MeasureDimension) -> Double {
        [start.width, start.depth, start.height][dimension.rawValue]
    }

    /// Gentle warnings: a reading far bigger than usual (often the wall
    /// behind), or a small item that may be easier to size another way.
    private var sizeWarning: String? {
        if steps.hasStart, let current = steps.current, current != .height,
           let live = model.liveDistanceCm, live > max(typical(current) * 2.5, typical(current) + 60) {
            return "That looks too big. Make sure the ring is on the item, not the wall or floor behind it."
        }
        if let height = steps.value(.height), height < 40, steps.current == .width, !steps.hasStart {
            return "Small item? Typing the sizes or using a card in a photo may be easier."
        }
        return nil
    }

    private var floorWord: String { onSurface ? "desk or table" : "floor" }

    private var instruction: String {
        if let problem = model.problem { return problem }
        guard let current = steps.current else { return "Done" }
        if steps.hasStart {
            return current == .height
                ? "Now tilt up and aim at the very top."
                : (measureAtTop && model.topY != nil
                    ? "Move the ring to the opposite edge of the top, then tap Set end."
                    : "Move the ring along the \(floorWord) to the other edge, then tap Set end.")
        }
        if !model.surfaceUnderDot {
            return "Point at the \(floorWord) and move your phone a little until the dot lights up."
        }
        let onTop = measureAtTop && model.topY != nil
        switch current {
        case .width:
            return onTop
                ? "Put the ring on the LEFT edge of the top of the item, then tap Set start."
                : "Put the ring on the \(floorWord) right below the LEFT edge of the item, then tap Set start."
        case .depth:
            return onTop
                ? "Put the ring on the FRONT edge of the top of the item, then tap Set start."
                : "Put the ring on the \(floorWord) touching the FRONT edge of the item, then tap Set start."
        case .height:
            return "Put the ring on the \(floorWord) right at the bottom of the item, below its highest point, then tap Set start. Hold still when you tap."
        }
    }

    // MARK: Review

    private var reviewCard: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("Check the sizes")
                    .font(Typography.title)
                    .foregroundStyle(Theme.textPrimary)
                MeasureDiagram(highlight: nil)
                    .frame(height: 90)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                ForEach(MeasureDimension.allCases) { dimension in
                    HStack {
                        Circle().fill(dimension.color).frame(width: 12, height: 12)
                        Text(dimension.name.capitalized).font(Typography.headline)
                        Spacer()
                        Text(steps.value(dimension).map { Length.formatFurniture($0, system: unit) } ?? "–")
                            .font(Typography.headline)
                        Button("Redo") {
                            steps.remeasure(dimension)
                            model.clearStart()
                        }
                        .frame(minHeight: Theme.minTap)
                        .accessibilityLabel("Measure the \(dimension.name) again")
                    }
                    .foregroundStyle(Theme.textPrimary)
                }
                if steps.looksSwapped {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The width is smaller than the depth. Did you swap them?")
                            .font(Typography.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Swap width and depth") {
                            steps.swapWidthAndDepth()
                            model.syncLines(steps)
                        }
                        .font(Typography.headline)
                        .frame(minHeight: Theme.minTap)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                }
                Text("Camera sizes are usually within 1–2 in (3–5 cm) in good light, close up. They stay marked Estimated until you confirm them.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "Use these sizes", systemImage: "checkmark") {
                    let r = steps.results
                    onDone(r[0], r[1], r[2])
                    dismiss()
                }
            }
            .padding(Theme.Space.md)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .padding(Theme.Space.md)
        }
    }

    private func setPoint() {
        guard let current = steps.current else { return }
        if !steps.hasStart {
            if model.setStart(step: current.rawValue, color: current.uiColor) {
                steps.setStart()
                tapCount += 1
            }
            return
        }
        guard let distance = model.finish(), steps.setEnd(distanceCm: distance) else { return }
        tapCount += 1
        model.syncLines(steps)
    }
}

/// A simple sofa from the front-left, with an arrow for one size.
struct MeasureDiagram: View {
    let highlight: MeasureDimension?

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            // Sofa block seen at an angle: front face, top, and side.
            let front = CGRect(x: w * 0.12, y: h * 0.42, width: w * 0.62, height: h * 0.45)
            let shift = CGSize(width: w * 0.18, height: -h * 0.28)
            var outline = Path()
            outline.addRect(front)
            outline.move(to: front.origin)
            outline.addLine(to: CGPoint(x: front.minX + shift.width, y: front.minY + shift.height))
            outline.addLine(to: CGPoint(x: front.maxX + shift.width, y: front.minY + shift.height))
            outline.addLine(to: CGPoint(x: front.maxX + shift.width, y: front.maxY + shift.height))
            outline.addLine(to: CGPoint(x: front.maxX, y: front.maxY))
            outline.move(to: CGPoint(x: front.maxX, y: front.minY))
            outline.addLine(to: CGPoint(x: front.maxX + shift.width, y: front.minY + shift.height))
            context.stroke(outline, with: .color(.white.opacity(0.85)), lineWidth: 1.5)

            func arrow(_ a: CGPoint, _ b: CGPoint, _ dimension: MeasureDimension) {
                guard highlight == nil || highlight == dimension else { return }
                var line = Path()
                line.move(to: a); line.addLine(to: b)
                context.stroke(line, with: .color(dimension.color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                for (tip, from) in [(a, b), (b, a)] {
                    let angle = atan2(tip.y - from.y, tip.x - from.x)
                    var head = Path()
                    head.move(to: tip)
                    head.addLine(to: CGPoint(x: tip.x - 6 * cos(angle - 0.5), y: tip.y - 6 * sin(angle - 0.5)))
                    head.move(to: tip)
                    head.addLine(to: CGPoint(x: tip.x - 6 * cos(angle + 0.5), y: tip.y - 6 * sin(angle + 0.5)))
                    context.stroke(head, with: .color(dimension.color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
            let below = front.maxY + 4
            arrow(CGPoint(x: front.minX, y: below), CGPoint(x: front.maxX, y: below), .width)
            arrow(CGPoint(x: front.maxX + 4, y: front.maxY + 2), CGPoint(x: front.maxX + shift.width + 4, y: front.maxY + shift.height + 2), .depth)
            arrow(CGPoint(x: front.minX - 5, y: front.maxY), CGPoint(x: front.minX - 5, y: front.minY), .height)
        }
    }
}

/// Runs the AR session and turns the aiming dot into points in the room.
@MainActor
@Observable
final class ARMeasureModel: NSObject, ARSessionDelegate, ARSCNViewDelegate {
    /// True when the dot is over something ARKit can place a point on.
    private(set) var surfaceUnderDot = false
    /// Distance from the start point to the dot, while measuring.
    private(set) var liveDistanceCm: Double?
    /// A plain-words reason measuring can't work right now, if any.
    private(set) var problem: String?

    @ObservationIgnored weak var view: ARSCNView?
    @ObservationIgnored private var start: simd_float3?
    /// 0 width, 1 depth, 2 height: picks the guide plane for the end point.
    @ObservationIgnored private var step = 0
    @ObservationIgnored private var markers: [SCNNode] = []
    /// The last good point under the dot, and when it was found. Kept for a
    /// moment so the dot doesn't flicker when tracking blinks.
    @ObservationIgnored private var lastHit: (point: simd_float3, time: TimeInterval)?
    private static let holdTime: TimeInterval = 0.6

    func attach(_ view: ARSCNView) {
        self.view = view
        view.delegate = self
        view.session.delegate = self
        view.automaticallyUpdatesLighting = true

        // World tracking works on every ARKit iPhone; no LiDAR needed.
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        // Apple's built-in "move your phone" animation, shown until ARKit
        // has found a surface.
        let coaching = ARCoachingOverlayView()
        coaching.session = view.session
        coaching.goal = .anyPlane
        coaching.activatesAutomatically = true
        coaching.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(coaching)
        NSLayoutConstraint.activate([
            coaching.topAnchor.constraint(equalTo: view.topAnchor),
            coaching.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            coaching.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            coaching.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    /// The camera's position and the direction through the aiming dot.
    private func aimingRay() -> (origin: simd_float3, direction: simd_float3)? {
        guard let view, view.bounds.width > 0 else { return nil }
        let near = view.unprojectPoint(SCNVector3(Float(view.bounds.midX), Float(view.bounds.midY), 0))
        let far = view.unprojectPoint(SCNVector3(Float(view.bounds.midX), Float(view.bounds.midY), 1))
        let origin = simd_float3(near.x, near.y, near.z)
        let direction = simd_normalize(simd_float3(far.x, far.y, far.z) - origin)
        return (origin, direction)
    }

    /// A surface under the dot: a found flat surface, ARKit's guess at one,
    /// or a tracked speck on a textured surface (like the couch fabric).
    private func surfacePoint() -> simd_float3? {
        guard let view else { return nil }
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        // Every measurement starts on the floor (or a tabletop), so only
        // flat, level surfaces count. Walls are left out on purpose: aiming
        // at a small item used to land the point on the wall behind it.
        let tries: [(ARRaycastQuery.Target, ARRaycastQuery.TargetAlignment)] = [
            (.existingPlaneInfinite, .horizontal), (.existingPlaneGeometry, .horizontal), (.estimatedPlane, .horizontal),
        ]
        for (target, alignment) in tries {
            if let query = view.raycastQuery(from: center, allowing: target, alignment: alignment),
               let hit = view.session.raycast(query).first {
                let t = hit.worldTransform.columns.3
                return simd_float3(t.x, t.y, t.z)
            }
        }
        // No level surface found yet: a tracked speck, but only well below
        // the phone (the floor or something on it), never a wall at eye level.
        if let ray = aimingRay(), let points = view.session.currentFrame?.rawFeaturePoints?.points,
           let point = ARMeasure.nearestFeaturePoint(points, origin: ray.origin, direction: ray.direction),
           ray.origin.y - point.y > 0.4 {
            return point
        }
        return nil
    }

    /// The start point: a surface, or the last one found a moment ago.
    private func startCandidate(now: TimeInterval = CACurrentMediaTime()) -> simd_float3? {
        // Across the top: only the top plane counts, never what's behind.
        if topY != nil, measureAtTop, upcoming != .height {
            return topPlanePoint()
        }
        if let point = surfacePoint() {
            lastHit = (point, now)
            return point
        }
        if let lastHit, now - lastHit.time < Self.holdTime { return lastHit.point }
        return nil
    }

    /// The end point: where the dot meets the guide plane through the start
    /// (the floor for width and depth, a standing plane for height). Always
    /// available once the start is set, so it never flickers.
    private func endCandidate() -> simd_float3? {
        guard let start, let ray = aimingRay() else { return nil }
        if step == 2 {
            return ARMeasure.pointOnVerticalLine(base: start, origin: ray.origin, direction: ray.direction)
        }
        var plane = ARMeasure.guidePlane(for: step, start: start, cameraPosition: ray.origin)
        // Aiming almost level with the plane (a thin top seen from the
        // side) shoots the point far away. Use a standing plane through the
        // start, facing the phone, instead: the far edge lands on the item.
        if abs(simd_dot(ray.direction, plane.normal)) < ARMeasure.minGrazing {
            plane = ARMeasure.guidePlane(for: 2, start: start, cameraPosition: ray.origin)
        }
        if let point = ARMeasure.intersect(origin: ray.origin, direction: ray.direction, planePoint: plane.point, normal: plane.normal) {
            return point
        }
        return surfacePoint()
    }

    func setStart(step: Int, color: UIColor = .systemGreen) -> Bool {
        guard let point = steadyPoint(startCandidate()) else { return false }
        recent.removeAll()
        self.step = step
        start = point
        addMarker(at: point, color: color)
        surfaceUnderDot = true
        return true
    }

    /// The distance from the start point to the dot, in cm.
    func finish() -> Double? {
        guard let start, let end = steadyPoint(endCandidate()) else { return nil }
        recent.removeAll()
        shown = nil
        updateGuide(top: nil)
        let distance = ARMeasure.distanceCm(start, end)
        guard distance >= 1 else { return nil }
        lineEnds[step] = (start, end)
        if step == MeasureDimension.height.rawValue {
            topY = end.y
            heightBase = start
        }
        self.start = nil
        liveDistanceCm = nil
        clearMarkers()
        return distance
    }

    func clearStart() {
        recent.removeAll()
        updateGuide(top: nil)
        start = nil
        shown = nil
        liveDistanceCm = nil
        clearMarkers()
    }

    func pause() {
        view?.session.pause()
    }

    // MARK: Markers

    @ObservationIgnored private var guideNodes: [SCNNode] = []
    /// The next size to measure, and whether width and depth go across the
    /// item's top. Set by the screen.
    @ObservationIgnored var upcoming: MeasureDimension? {
        didSet { updateTopPlane() }
    }
    @ObservationIgnored var measureAtTop = true {
        didSet { updateTopPlane() }
    }
    /// Height of the item's top above the world origin, once height is
    /// measured, and the floor point it was measured from.
    private(set) var topY: Float?
    @ObservationIgnored private var heightBase: simd_float3?
    @ObservationIgnored private var topPlaneNode: SCNNode?

    /// A faint square at the top's height, so it's clear where width and
    /// depth points will land.
    private func updateTopPlane() {
        topPlaneNode?.removeFromParentNode()
        topPlaneNode = nil
        guard measureAtTop, upcoming != .height, let topY, let base = heightBase, let root = view?.scene.rootNode else { return }
        let plane = SCNPlane(width: 1.2, height: 1.2)
        plane.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.12)
        plane.firstMaterial?.isDoubleSided = true
        let node = SCNNode(geometry: plane)
        node.simdPosition = simd_float3(base.x, topY, base.z)
        node.eulerAngles.x = -.pi / 2
        root.addChildNode(node)
        topPlaneNode = node
    }

    /// Where the aim meets the top plane, when measuring across the top.
    private func topPlanePoint() -> simd_float3? {
        guard measureAtTop, let upcoming, upcoming != .height, let topY, let ray = aimingRay() else { return nil }
        // Aiming almost level with the top makes tiny moves jump far away.
        guard abs(ray.direction.y) > ARMeasure.minGrazing else { return nil }
        return ARMeasure.intersect(origin: ray.origin, direction: ray.direction,
                                   planePoint: simd_float3(0, topY, 0), normal: simd_float3(0, 1, 0))
    }
    @ObservationIgnored private var liveNodes: [SCNNode] = []
    /// The color of the size being measured, for the live marker.
    @ObservationIgnored var currentColor: UIColor = .systemBlue

    /// Shows exactly where the point would land: a flat ring on the floor
    /// before the start is set, then a line from the start to the aim. So
    /// it's obvious if the point is somewhere unexpected.
    private func updateLiveMarker(_ point: simd_float3?) {
        liveNodes.forEach { $0.removeFromParentNode() }
        liveNodes.removeAll()
        guard let point, let root = view?.scene.rootNode else { return }
        let ring = SCNTube(innerRadius: 0.012, outerRadius: 0.02, height: 0.001)
        ring.firstMaterial?.diffuse.contents = currentColor
        let ringNode = SCNNode(geometry: ring)
        ringNode.simdPosition = point
        root.addChildNode(ringNode)
        liveNodes.append(ringNode)
        if let start, simd_distance(start, point) > 0.005 {
            let rod = SCNCylinder(radius: 0.003, height: CGFloat(simd_distance(start, point)))
            rod.firstMaterial?.diffuse.contents = currentColor
            let line = SCNNode(geometry: rod)
            line.simdPosition = (start + point) / 2
            line.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: simd_normalize(point - start))
            root.addChildNode(line)
            liveNodes.append(line)
        }
    }

    /// While measuring height: a thin line rising from the floor point and a
    /// dot where the top currently lands, so you can see what's measured.
    private func updateGuide(top: simd_float3?) {
        guideNodes.forEach { $0.removeFromParentNode() }
        guideNodes.removeAll()
        guard step == 2, let start, let root = view?.scene.rootNode else { return }
        let pole = SCNCylinder(radius: 0.002, height: 2.5)
        pole.firstMaterial?.diffuse.contents = UIColor.systemGreen.withAlphaComponent(0.6)
        let line = SCNNode(geometry: pole)
        line.simdPosition = start + simd_float3(0, 1.25, 0)
        root.addChildNode(line)
        guideNodes.append(line)
        if let top {
            let dot = SCNNode(geometry: SCNSphere(radius: 0.008))
            dot.geometry?.firstMaterial?.diffuse.contents = UIColor.systemGreen
            dot.simdPosition = top
            root.addChildNode(dot)
            guideNodes.append(dot)
        }
    }

    /// Where each finished size was measured, so it stays drawn.
    @ObservationIgnored private var lineEnds: [Int: (simd_float3, simd_float3)] = [:]
    @ObservationIgnored private var lineNodes: [SCNNode] = []

    /// Draws a colored, labeled line ("W 82″") for every finished size,
    /// and removes lines for sizes that were undone or are being redone.
    func syncLines(_ steps: MeasureSteps) {
        if steps.value(.height) == nil {
            topY = nil
            heightBase = nil
        }
        defer { updateTopPlane() }
        lineNodes.forEach { $0.removeFromParentNode() }
        lineNodes.removeAll()
        for dimension in MeasureDimension.allCases {
            guard let value = steps.value(dimension) else {
                lineEnds[dimension.rawValue] = nil
                continue
            }
            guard let (a, b) = lineEnds[dimension.rawValue], let root = view?.scene.rootNode else { continue }
            let length = simd_distance(a, b)
            let cylinder = SCNCylinder(radius: 0.004, height: CGFloat(length))
            cylinder.firstMaterial?.diffuse.contents = dimension.uiColor
            let line = SCNNode(geometry: cylinder)
            line.simdPosition = (a + b) / 2
            line.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: simd_normalize(b - a))
            root.addChildNode(line)
            lineNodes.append(line)

            let text = SCNText(string: "\(dimension.short) \(Length.formatFurniture(value, system: UnitSystem.deviceDefault))", extrusionDepth: 0)
            text.font = .systemFont(ofSize: 10, weight: .bold)
            text.firstMaterial?.diffuse.contents = dimension.uiColor
            text.firstMaterial?.isDoubleSided = true
            let label = SCNNode(geometry: text)
            label.scale = SCNVector3(0.004, 0.004, 0.004)
            label.simdPosition = (a + b) / 2 + simd_float3(0, 0.03, 0)
            label.constraints = [SCNBillboardConstraint()]
            root.addChildNode(label)
            lineNodes.append(label)
        }
    }

    private func addMarker(at point: simd_float3, color: UIColor = .systemGreen) {
        let sphere = SCNSphere(radius: 0.006)
        sphere.firstMaterial?.diffuse.contents = color
        let node = SCNNode(geometry: sphere)
        node.simdPosition = point
        view?.scene.rootNode.addChildNode(node)
        markers.append(node)
    }

    private func clearMarkers() {
        markers.forEach { $0.removeFromParentNode() }
        markers.removeAll()
    }

    // MARK: Every frame

    nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        Task { @MainActor in self.updateDot() }
    }

    /// Runs every frame, but only touches what's on screen when it changes.
    @ObservationIgnored private var shown: simd_float3?

    /// The last ~15 frames' readings, for a steady point when Set is tapped.
    @ObservationIgnored private var recent: [simd_float3] = []
    /// A gentle hint shown under the instructions, like "Move closer".
    private(set) var hint: String?

    private func steadyPoint(_ fallback: simd_float3?) -> simd_float3? {
        ARMeasure.median(recent) ?? fallback
    }

    private func updateDot() {
        let point = start == nil ? startCandidate() : endCandidate()
        if surfaceUnderDot != (point != nil) { surfaceUnderDot = point != nil }
        if let point {
            recent.append(point)
            if recent.count > 15 { recent.removeFirst(recent.count - 15) }
        } else {
            recent.removeAll()
        }
        var newHint: String?
        if let point, let ray = aimingRay(), simd_distance(point, ray.origin) > 2.5 {
            newHint = "Move closer for a more accurate size."
        }
        if newHint != hint { hint = newHint }
        updateGuide(top: point)
        updateLiveMarker(point)
        if let start, let point {
            shown = ARMeasure.smooth(shown, toward: point)
            let distance = (ARMeasure.distanceCm(start, shown!) * 2).rounded() / 2
            if distance != liveDistanceCm { liveDistanceCm = distance }
        }
    }

    // MARK: Tracking problems

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let message: String?
        switch camera.trackingState {
        case .normal, .notAvailable: message = nil
        case .limited(.excessiveMotion): message = "Move your phone a bit more slowly."
        case .limited(.insufficientFeatures): message = "Point at something with more detail, like a rug or the edge of the furniture, and turn on a light."
        case .limited(.initializing), .limited(.relocalizing): message = nil
        case .limited: message = nil
        }
        Task { @MainActor in self.problem = message }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let denied = (error as? ARError)?.code == .cameraUnauthorized
        Task { @MainActor in
            self.problem = denied
                ? "Camera access is off. Allow it in Settings → Interior Design → Camera."
                : "The camera couldn't start. Close this screen and try again."
        }
    }
}

private struct ARViewContainer: UIViewRepresentable {
    let model: ARMeasureModel

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        model.attach(view)
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {}

    static func dismantleUIView(_ view: ARSCNView, coordinator: ()) {
        view.session.pause()
    }
}
