import SwiftUI

/// Measuring from a single photo: tap both ends of something of known size
/// (a credit card, a sheet of paper, a door), then both ends of the
/// furniture's width and height.
struct ReferenceMeasureView: View {
    let image: UIImage
    let onDone: (_ width: Double, _ height: Double) -> Void

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue

    @State private var reference: ReferenceObject = .creditCard
    @State private var customLengthCm: Double = 100
    /// Taps, in the photo's own coordinates: reference (2), width (2), height (2).
    @State private var taps: [CGPoint] = []
    @State private var problem: String?

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    private var steps: [String] {
        ["one end of the \(referenceName)", "the other end of the \(referenceName)",
         "the left edge of the furniture", "its right edge",
         "the top of the furniture", "the floor under it"]
    }

    private var referenceName: String {
        reference == .custom ? "thing you measured" : reference.title.components(separatedBy: " (").first!.lowercased()
    }

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            Picker("Reference", selection: $reference) {
                ForEach(ReferenceObject.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .onChange(of: reference) { _, _ in taps = [] }

            if reference == .custom {
                LengthField(title: "Its length", cm: $customLengthCm, unit: unit, range: 1...1000, scale: .furniture)
            }

            Text(taps.count < steps.count ? "Tap \(steps[taps.count])" : "All set")
                .font(Typography.headline)
                .foregroundStyle(Theme.textPrimary)

            GeometryReader { geo in
                let fitted = fit(image.size, in: geo.size)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: fitted.width, height: fitted.height)
                    Canvas { context, _ in
                        let colors: [Color] = [Theme.accent, Theme.accent, .orange, .orange, .blue, .blue]
                        for (i, tap) in taps.enumerated() {
                            let p = CGPoint(x: tap.x * fitted.scale, y: tap.y * fitted.scale)
                            context.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color(colors[i]))
                            if i % 2 == 1 {
                                let q = CGPoint(x: taps[i - 1].x * fitted.scale, y: taps[i - 1].y * fitted.scale)
                                var line = Path()
                                line.move(to: q)
                                line.addLine(to: p)
                                context.stroke(line, with: .color(colors[i]), lineWidth: 3)
                            }
                        }
                    }
                    .frame(width: fitted.width, height: fitted.height)
                }
                .frame(width: fitted.width, height: fitted.height)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    guard taps.count < steps.count else { return }
                    // Store taps in photo coordinates so they don't depend on screen size.
                    taps.append(CGPoint(x: location.x / fitted.scale, y: location.y / fitted.scale))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }

    private func finish() {
        let known = reference.lengthCm ?? customLengthCm
        guard let scale = ReferenceScale(referenceStart: taps[0], referenceEnd: taps[1], knownLengthCm: known),
              let width = scale.length(from: taps[2], to: taps[3]),
              let height = scale.length(from: taps[4], to: taps[5]) else {
            problem = "Some taps are too close together. Undo and try again, zooming in on the photo if needed."
            return
        }
        // The flow moves on to the confirm screen itself.
        onDone(width, height)
    }

    /// The image's size when fitted into the space, and the scale used.
    private func fit(_ size: CGSize, in space: CGSize) -> (width: CGFloat, height: CGFloat, scale: CGFloat) {
        let scale = min(space.width / max(size.width, 1), space.height / max(size.height, 1))
        return (size.width * scale, size.height * scale, scale)
    }
}
