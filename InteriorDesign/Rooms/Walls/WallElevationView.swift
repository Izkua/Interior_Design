import SwiftUI
import UIKit

/// A flat front view of one wall: floor to ceiling, left corner to right
/// corner, as if you stood in the room facing it. Shows doors, windows,
/// outlets, furniture standing against it, an eye-level line, and the
/// decor, which can be dragged and snaps to helpful lines.
struct WallElevationView: View {
    let wallLength: Double
    let ceiling: Double
    let features: [FixedFeature]
    let furniture: [WallFurniture]
    let decor: [WallDecor]
    /// Pieces with a warning, outlined in red.
    let problemIDs: Set<UUID>
    let corners: [Point2D]
    let wall: Int
    let unit: UnitSystem
    @Binding var selectedID: UUID?
    /// Called once when a drag ends, with the piece's new spot.
    let onMove: (WallDecor) -> Void

    /// The piece being dragged, where it would land, and the lines it
    /// snapped to. Kept here until the finger lifts, then saved once.
    @State private var drag: (start: WallDecor, preview: WallDecor, guides: [DecorGuide])?

    var body: some View {
        GeometryReader { geo in
            let map = WallMap(size: geo.size, wallLength: wallLength, ceiling: ceiling)
            ZStack(alignment: .bottomTrailing) {
                Canvas { ctx, _ in draw(in: &ctx, map: map) }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedID = nil }
                    .accessibilityHidden(true)

                ForEach(shownDecor) { piece in
                    pieceView(piece, map: map)
                }

                MiniPlan(corners: corners, wall: wall)
                    .frame(width: 34, height: 34)
                    .padding(6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The saved pieces, with the one being dragged swapped for its preview.
    private var shownDecor: [WallDecor] {
        guard let drag else { return decor }
        return decor.map { $0.id == drag.preview.id ? drag.preview : $0 }
    }

    // MARK: One piece

    private func pieceView(_ piece: WallDecor, map: WallMap) -> some View {
        let selected = piece.id == selectedID
        let warn = problemIDs.contains(piece.id)
        let w = max(piece.widthCm * map.scale, 2)
        let h = max(piece.heightCm * map.scale, 2)
        let tint = warn ? Theme.danger : Theme.accent

        return ZStack {
            shape(for: piece.kind)
                .fill(tint.opacity(selected ? 0.35 : 0.18))
            shape(for: piece.kind)
                .stroke(tint, lineWidth: selected ? 2 : 1)
            if w >= 24 && h >= 24 {
                Image(systemName: piece.kind.symbol)
                    .font(.system(size: min(w, h) * 0.35))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: w, height: h)
        // Thin things like shelves still get a finger-sized target.
        .frame(width: max(w, Theme.minTap), height: max(h, Theme.minTap))
        .contentShape(Rectangle())
        .position(map.point(x: piece.centerX, y: piece.centerY))
        .onTapGesture { selectedID = piece.id }
        .gesture(dragGesture(for: piece, map: map))
        .accessibilityElement()
        .accessibilityLabel("\(piece.name), \(Length.formatFurniture(piece.widthCm, system: unit)) wide")
        .accessibilityHint("Drag to move it on the wall")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func shape(for kind: DecorKind) -> AnyShape {
        switch kind {
        case .mirror: return AnyShape(Ellipse())
        case .clock: return AnyShape(Circle())
        default: return AnyShape(RoundedRectangle(cornerRadius: 2))
        }
    }

    private func dragGesture(for piece: WallDecor, map: WallMap) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = drag?.start ?? piece
                if drag == nil { selectedID = piece.id }
                var moved = start
                moved.centerX = start.centerX + value.translation.width / map.scale
                moved.centerY = start.centerY - value.translation.height / map.scale
                moved = WallDecorGeometry.clamped(moved, wallLength: wallLength, ceiling: ceiling)
                let snap = WallDecorGeometry.snapped(moved, wallLength: wallLength, others: decor, furniture: furniture)
                let landed = WallDecorGeometry.clamped(snap.decor, wallLength: wallLength, ceiling: ceiling)
                if let old = drag, old.guides != snap.guides, !snap.guides.isEmpty {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                drag = (start, landed, snap.guides)
            }
            .onEnded { _ in
                if let drag { onMove(drag.preview) }
                drag = nil
            }
    }

    // MARK: Drawing

    private func draw(in ctx: inout GraphicsContext, map: WallMap) {
        let wallRect = map.rect(WallRect(minX: 0, minY: 0, maxX: wallLength, maxY: ceiling))

        // The wall, the floor line, and the ceiling.
        ctx.fill(Path(wallRect), with: .color(Theme.surfaceAlt))
        var floor = Path()
        floor.move(to: CGPoint(x: wallRect.minX - 6, y: wallRect.maxY))
        floor.addLine(to: CGPoint(x: wallRect.maxX + 6, y: wallRect.maxY))
        ctx.stroke(floor, with: .color(Theme.textSecondary), lineWidth: 2)
        ctx.stroke(Path(wallRect), with: .color(Theme.line), lineWidth: 1)

        // Eye level: where the middle of art usually goes.
        let eyeY = map.point(x: 0, y: WallDecorGeometry.eyeLevelCm).y
        var eye = Path()
        eye.move(to: CGPoint(x: wallRect.minX, y: eyeY))
        eye.addLine(to: CGPoint(x: wallRect.maxX, y: eyeY))
        ctx.stroke(eye, with: .color(Theme.accent.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        ctx.draw(
            Text("Eye level").font(.caption2).foregroundColor(Theme.accent),
            at: CGPoint(x: wallRect.minX + 4, y: eyeY - 2),
            anchor: .bottomLeading
        )

        // Furniture standing against the wall: gray silhouettes.
        for f in furniture {
            let r = map.rect(f.rect)
            ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Theme.textSecondary.opacity(0.25)))
            if r.width > 50 && r.height > 14 {
                ctx.draw(
                    Text(f.name).font(.caption2).foregroundColor(Theme.textSecondary),
                    at: CGPoint(x: r.midX, y: r.midY)
                )
            }
        }

        // Doors, windows, outlets.
        for feature in features {
            let r = map.rect(WallDecorGeometry.rect(for: feature, ceiling: ceiling))
            switch feature.kind {
            case .door:
                ctx.fill(Path(r), with: .color(Theme.background))
                ctx.stroke(Path(r), with: .color(Theme.textSecondary), lineWidth: 1.5)
            case .window:
                ctx.fill(Path(r), with: .color(Theme.accent.opacity(0.08)))
                ctx.stroke(Path(r), with: .color(Theme.textSecondary), lineWidth: 1.5)
                var bars = Path()
                bars.move(to: CGPoint(x: r.midX, y: r.minY))
                bars.addLine(to: CGPoint(x: r.midX, y: r.maxY))
                ctx.stroke(bars, with: .color(Theme.textSecondary.opacity(0.6)), lineWidth: 1)
            case .outlet:
                ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(Theme.textSecondary.opacity(0.6)))
            }
            if feature.kind != .outlet, r.width > 30 {
                ctx.draw(
                    Text(feature.kind.title).font(.caption2).foregroundColor(Theme.textSecondary),
                    at: CGPoint(x: r.midX, y: r.minY + 8)
                )
            }
        }

        // Lines the dragged piece snapped to.
        for guide in drag?.guides ?? [] {
            var line = Path()
            switch guide.axis {
            case .vertical:
                let x = map.point(x: guide.position, y: 0).x
                line.move(to: CGPoint(x: x, y: wallRect.minY))
                line.addLine(to: CGPoint(x: x, y: wallRect.maxY))
            case .horizontal:
                let y = map.point(x: 0, y: guide.position).y
                line.move(to: CGPoint(x: wallRect.minX, y: y))
                line.addLine(to: CGPoint(x: wallRect.maxX, y: y))
            }
            ctx.stroke(line, with: .color(Theme.accent), lineWidth: 1)
        }

        // Wall length under the floor, ceiling height on the left.
        ctx.draw(
            Text(Length.format(wallLength, system: unit)).font(.caption).foregroundColor(Theme.textSecondary),
            at: CGPoint(x: wallRect.midX, y: wallRect.maxY + 4),
            anchor: .top
        )
        ctx.draw(
            Text(Length.format(ceiling, system: unit)).font(.caption2).foregroundColor(Theme.textSecondary),
            at: CGPoint(x: wallRect.minX + 4, y: wallRect.maxY - 4),
            anchor: .bottomLeading
        )
    }
}

/// Turns wall centimeters (x along the wall, y up from the floor) into
/// points on screen, fitting the whole wall in the view.
struct WallMap {
    let scale: Double
    let originX: Double
    let floorY: Double

    init(size: CGSize, wallLength: Double, ceiling: Double) {
        let side = 12.0
        let top = 16.0
        let bottom = 26.0
        let usableW = max(Double(size.width) - side * 2, 1)
        let usableH = max(Double(size.height) - top - bottom, 1)
        scale = min(usableW / max(wallLength, 1), usableH / max(ceiling, 1))
        originX = (Double(size.width) - wallLength * scale) / 2
        floorY = top + (usableH + ceiling * scale) / 2
    }

    func point(x: Double, y: Double) -> CGPoint {
        CGPoint(x: originX + x * scale, y: floorY - y * scale)
    }

    func rect(_ r: WallRect) -> CGRect {
        let topLeft = point(x: r.minX, y: r.maxY)
        return CGRect(x: topLeft.x, y: topLeft.y, width: r.width * scale, height: r.height * scale)
    }
}

/// A tiny outline of the room with the chosen wall drawn thick, so it's
/// clear which wall the front view shows.
struct MiniPlan: View {
    let corners: [Point2D]
    let wall: Int

    var body: some View {
        Canvas { ctx, size in
            guard corners.count >= 3 else { return }
            let xs = corners.map(\.x), ys = corners.map(\.y)
            let minX = xs.min()!, minY = ys.min()!
            let w = max(xs.max()! - minX, 1), h = max(ys.max()! - minY, 1)
            let s = min((size.width - 8) / w, (size.height - 8) / h)
            let ox = (size.width - w * s) / 2, oy = (size.height - h * s) / 2
            func p(_ c: Point2D) -> CGPoint { CGPoint(x: ox + (c.x - minX) * s, y: oy + (c.y - minY) * s) }

            var outline = Path()
            outline.move(to: p(corners[0]))
            for c in corners.dropFirst() { outline.addLine(to: p(c)) }
            outline.closeSubpath()
            ctx.fill(outline, with: .color(Theme.surface))
            ctx.stroke(outline, with: .color(Theme.textSecondary.opacity(0.6)), lineWidth: 1)

            let i = ((wall % corners.count) + corners.count) % corners.count
            var chosen = Path()
            chosen.move(to: p(corners[i]))
            chosen.addLine(to: p(corners[(i + 1) % corners.count]))
            ctx.stroke(chosen, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .background(Theme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
    }
}
