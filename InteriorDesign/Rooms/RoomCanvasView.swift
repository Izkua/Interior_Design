import SwiftUI

// MARK: - Coordinate conversion

/// Converts between room centimeters and points on screen, fitting the
/// whole room inside a canvas with some padding.
struct CanvasSpace {
    let scale: CGFloat
    private let originX: CGFloat
    private let originY: CGFloat
    private let minX: Double
    private let minY: Double

    init(corners: [Point2D], size: CGSize, padding: CGFloat) {
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        let lowX = xs.min() ?? 0
        let highX = xs.max() ?? 1
        let lowY = ys.min() ?? 0
        let highY = ys.max() ?? 1
        let roomWidth = CGFloat(max(highX - lowX, 1))
        let roomHeight = CGFloat(max(highY - lowY, 1))
        let availableWidth = max(size.width - 2 * padding, 1)
        let availableHeight = max(size.height - 2 * padding, 1)
        let fit = min(availableWidth / roomWidth, availableHeight / roomHeight)

        self.scale = fit
        self.minX = lowX
        self.minY = lowY
        self.originX = (size.width - roomWidth * fit) / 2
        self.originY = (size.height - roomHeight * fit) / 2
    }

    func viewPoint(_ p: Point2D) -> CGPoint {
        CGPoint(
            x: originX + CGFloat(p.x - minX) * scale,
            y: originY + CGFloat(p.y - minY) * scale
        )
    }

    func roomPoint(_ point: CGPoint) -> Point2D {
        Point2D(
            x: Double((point.x - originX) / scale) + minX,
            y: Double((point.y - originY) / scale) + minY
        )
    }
}

// MARK: - Drawing

/// Draws the room, its walls, doors, windows, outlets, and wall lengths.
enum RoomPlanPainter {
    static func paint(
        _ ctx: inout GraphicsContext,
        corners: [Point2D],
        features: [FixedFeature],
        selectedID: UUID?,
        space: CanvasSpace,
        unit: UnitSystem
    ) {
        let count = corners.count
        guard count >= 3 else { return }
        let points = corners.map { space.viewPoint($0) }

        // Floor and walls.
        var outline = Path()
        outline.move(to: points[0])
        for point in points.dropFirst() {
            outline.addLine(to: point)
        }
        outline.closeSubpath()
        ctx.fill(outline, with: .color(Theme.surfaceAlt))
        ctx.stroke(
            outline,
            with: .color(Theme.textPrimary),
            style: StrokeStyle(lineWidth: 6, lineJoin: .round)
        )

        // Doors, windows, and outlets. Each is drawn in its own coordinate
        // system: x runs along the wall, and +y points into the room.
        for feature in features {
            let wall = ((feature.wall % count) + count) % count
            let a = points[wall]
            let b = points[(wall + 1) % count]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let length = max(hypot(dx, dy), 0.001)
            let ux = dx / length
            let uy = dy / length
            let along = CGFloat(feature.offsetCm) * space.scale
            let center = CGPoint(x: a.x + ux * along, y: a.y + uy * along)

            var local = ctx
            local.translateBy(x: center.x, y: center.y)
            local.rotate(by: .radians(Double(atan2(uy, ux))))
            drawFeature(
                &local,
                feature: feature,
                scale: space.scale,
                selected: feature.id == selectedID
            )
        }

        // Wall lengths, just outside each wall.
        for i in 0..<count {
            let a = points[i]
            let b = points[(i + 1) % count]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let length = max(hypot(dx, dy), 0.001)
            // Outward normal for corners listed clockwise on screen.
            let nx = dy / length
            let ny = -dx / length
            let position = CGPoint(
                x: (a.x + b.x) / 2 + nx * 22,
                y: (a.y + b.y) / 2 + ny * 22
            )
            let text = Text(Length.format(PlanGeometry.wallLength(i, corners: corners), system: unit))
                .font(Typography.caption)
                .foregroundColor(Theme.textSecondary)
            ctx.draw(text, at: position, anchor: .center)
        }
    }

    private static func drawFeature(
        _ ctx: inout GraphicsContext,
        feature: FixedFeature,
        scale: CGFloat,
        selected: Bool
    ) {
        let accent = Theme.accent
        let width = max(CGFloat(feature.widthCm) * scale, 14)

        switch feature.kind {
        case .door:
            // Open up the wall where the door is.
            ctx.fill(Path(CGRect(x: -width / 2, y: -5, width: width, height: 5)), with: .color(Theme.surface))
            ctx.fill(Path(CGRect(x: -width / 2, y: 0, width: width, height: 5)), with: .color(Theme.surfaceAlt))

            // The door leaf, drawn fully open, and the quarter-circle it
            // sweeps through. The hinge end and swing side come from the
            // feature, so the plan shows the space the door needs.
            let hingeX: CGFloat = feature.hingeAtStart ? -width / 2 : width / 2
            let towardLatch: CGFloat = feature.hingeAtStart ? 1 : -1
            let swing: CGFloat = feature.opensInward ? 1 : -1

            var leaf = Path()
            leaf.move(to: CGPoint(x: hingeX, y: 0))
            leaf.addLine(to: CGPoint(x: hingeX, y: swing * width))
            ctx.stroke(leaf, with: .color(accent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

            var arc = Path()
            let steps = 14
            for step in 0...steps {
                let angle = Double(step) / Double(steps) * (Double.pi / 2)
                let point = CGPoint(
                    x: hingeX + towardLatch * width * CGFloat(cos(angle)),
                    y: swing * width * CGFloat(sin(angle))
                )
                if step == 0 {
                    arc.move(to: point)
                } else {
                    arc.addLine(to: point)
                }
            }
            ctx.stroke(
                arc,
                with: .color(accent.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
            )

        case .window:
            let frame = CGRect(x: -width / 2, y: -4, width: width, height: 8)
            ctx.fill(Path(frame), with: .color(Theme.surface))
            ctx.stroke(Path(frame), with: .color(accent), lineWidth: 2)
            var glass = Path()
            glass.move(to: CGPoint(x: -width / 2, y: 0))
            glass.addLine(to: CGPoint(x: width / 2, y: 0))
            ctx.stroke(glass, with: .color(accent), lineWidth: 1)

        case .outlet:
            let dot = Path(ellipseIn: CGRect(x: -8, y: -8, width: 16, height: 16))
            ctx.fill(dot, with: .color(Theme.surface))
            ctx.stroke(dot, with: .color(accent), lineWidth: 2)
            var prongs = Path()
            prongs.move(to: CGPoint(x: -2.5, y: -3))
            prongs.addLine(to: CGPoint(x: -2.5, y: 3))
            prongs.move(to: CGPoint(x: 2.5, y: -3))
            prongs.addLine(to: CGPoint(x: 2.5, y: 3))
            ctx.stroke(prongs, with: .color(accent), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }

        if selected {
            let ring = Path(
                roundedRect: CGRect(x: -width / 2 - 8, y: -16, width: width + 16, height: 32),
                cornerRadius: 12
            )
            ctx.stroke(ring, with: .color(accent.opacity(0.9)), lineWidth: 2)
        }
    }
}

// MARK: - The interactive plan

/// A top-down plan of the room, drawn to scale. Doors, windows, and
/// outlets can be dragged and snap to the nearest wall.
struct RoomCanvasView: View {
    let room: Room
    @Binding var selectedFeatureID: UUID?
    let unit: UnitSystem

    @State private var draggingID: UUID?

    var body: some View {
        // Reading these here makes the view redraw when they change.
        let corners = room.corners
        let features = room.features
        let selectedID = selectedFeatureID
        let unit = self.unit

        GeometryReader { geo in
            let space = CanvasSpace(corners: corners, size: geo.size, padding: 56)
            Canvas { context, _ in
                RoomPlanPainter.paint(
                    &context,
                    corners: corners,
                    features: features,
                    selectedID: selectedID,
                    space: space,
                    unit: unit
                )
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(space: space))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Room plan, \(Length.format(room.width, system: unit)) by \(Length.format(room.length, system: unit))")
        .accessibilityHint("Use the list below to review doors, windows, and outlets.")
    }

    // MARK: Dragging

    private func dragGesture(space: CanvasSpace) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if draggingID == nil {
                    if let hit = feature(near: value.startLocation, space: space) {
                        draggingID = hit.id
                        selectedFeatureID = hit.id
                    } else {
                        selectedFeatureID = nil
                        return
                    }
                }
                guard
                    let id = draggingID,
                    let index = room.features.firstIndex(where: { $0.id == id })
                else { return }

                let point = space.roomPoint(value.location)
                let target = PlanGeometry.nearestWall(to: point, corners: room.corners)
                let wallLength = PlanGeometry.wallLength(target.wall, corners: room.corners)
                room.features[index].wall = target.wall
                room.features[index].offsetCm = PlanGeometry.clampOffset(
                    target.offset,
                    width: room.features[index].widthCm,
                    wallLength: wallLength
                )
            }
            .onEnded { _ in
                draggingID = nil
                room.updatedAt = Date()
            }
    }

    /// The feature closest to a touch, if one is within reach of a fingertip.
    private func feature(near location: CGPoint, space: CanvasSpace) -> FixedFeature? {
        var best: FixedFeature?
        var bestDistance = CGFloat(34)
        for feature in room.features {
            let spot = PlanGeometry.point(
                onWall: feature.wall,
                offset: feature.offsetCm,
                corners: room.corners
            )
            let center = space.viewPoint(spot)
            let distance = hypot(center.x - location.x, center.y - location.y)
            if distance < bestDistance {
                bestDistance = distance
                best = feature
            }
        }
        return best
    }
}

// MARK: - Small preview for lists

struct RoomThumbnail: View {
    let corners: [Point2D]

    var body: some View {
        Canvas { context, size in
            guard corners.count >= 3 else { return }
            let space = CanvasSpace(corners: corners, size: size, padding: 12)
            let points = corners.map { space.viewPoint($0) }
            var outline = Path()
            outline.move(to: points[0])
            for point in points.dropFirst() {
                outline.addLine(to: point)
            }
            outline.closeSubpath()
            context.fill(outline, with: .color(Theme.surface))
            context.stroke(
                outline,
                with: .color(Theme.textPrimary),
                style: StrokeStyle(lineWidth: 3, lineJoin: .round)
            )
        }
        .accessibilityHidden(true)
    }
}
