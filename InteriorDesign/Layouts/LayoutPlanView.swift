import SwiftUI

/// A top-down skeleton of a layout: the room, its doors and windows, and
/// each item as a soft colored box with its name. A thicker edge marks the
/// item's front.
struct LayoutPlanView: View {
    let room: LayoutRoom
    let placed: [PlacedItem]
    let unit: UnitSystem
    var selectedID: UUID? = nil
    /// Items breaking a rule, drawn in red.
    var problemIDs: Set<UUID> = []
    var showWallLengths = true
    /// When set, the plan keeps this scale instead of fitting the room;
    /// used while dragging so the plan does not shift under the finger.
    var space: CanvasSpace? = nil

    static let padding: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let space = self.space ?? CanvasSpace(corners: room.corners, size: geo.size, padding: Self.padding)
            Canvas { context, _ in
                RoomPlanPainter.paint(
                    &context,
                    corners: room.corners,
                    features: room.features,
                    selectedID: nil,
                    space: space,
                    unit: unit,
                    showWallLengths: showWallLengths
                )
                // Rugs first, so everything else sits on top of them.
                for item in placed.sorted(by: { $0.item.liesFlat && !$1.item.liesFlat }) {
                    LayoutPlanPainter.draw(
                        &context,
                        item,
                        space: space,
                        selected: item.item.id == selectedID,
                        problem: problemIDs.contains(item.item.id)
                    )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Floor plan with \(placed.map(\.item.name).joined(separator: ", "))")
    }
}

enum LayoutPlanPainter {
    static func draw(_ ctx: inout GraphicsContext, _ item: PlacedItem, space: CanvasSpace, selected: Bool, problem: Bool) {
        let box = item.footprint
        let topLeft = space.viewPoint(Point2D(x: box.minX, y: box.minY))
        let bottomRight = space.viewPoint(Point2D(x: box.maxX, y: box.maxY))
        let rect = CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
        let color = problem ? Theme.danger : item.item.type.planColor
        let shape = Path(roundedRect: rect, cornerRadius: item.item.liesFlat ? 2 : 5)

        ctx.fill(shape, with: .color(color.opacity(item.item.liesFlat ? 0.18 : 0.35)))
        ctx.stroke(
            shape,
            with: .color(color),
            style: StrokeStyle(lineWidth: selected ? 3 : 1.5, dash: item.item.liesFlat ? [4, 3] : [])
        )

        // The front edge, so you can see which way a sofa or desk faces.
        if !item.item.liesFlat {
            var edge = Path()
            let f = item.front
            if f.y > 0 { edge.move(to: CGPoint(x: rect.minX + 4, y: rect.maxY)); edge.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.maxY)) }
            if f.y < 0 { edge.move(to: CGPoint(x: rect.minX + 4, y: rect.minY)); edge.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.minY)) }
            if f.x > 0 { edge.move(to: CGPoint(x: rect.maxX, y: rect.minY + 4)); edge.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 4)) }
            if f.x < 0 { edge.move(to: CGPoint(x: rect.minX, y: rect.minY + 4)); edge.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 4)) }
            ctx.stroke(edge, with: .color(color), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }

        if selected {
            ctx.stroke(Path(roundedRect: rect.insetBy(dx: -4, dy: -4), cornerRadius: 8), with: .color(Theme.accent), lineWidth: 2)
        }

        // The longest form of the name that fits: the full name, its first
        // word, or its first letter. Tall, thin boxes write it sideways.
        let first = item.item.name.split(separator: " ").first.map(String.init) ?? item.item.name
        let options = [item.item.name, first, String(item.item.name.prefix(1))]
        let sideways = rect.height > rect.width * 1.4
        let room = (sideways ? rect.height : rect.width) - 6
        for (index, option) in options.enumerated() {
            let resolved = ctx.resolve(Text(option).font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.textPrimary))
            let width = resolved.measure(in: CGSize(width: 1_000, height: 30)).width
            guard width <= room || index == options.count - 1 else { continue }
            if sideways && width > rect.width - 6 {
                var turned = ctx
                turned.translateBy(x: rect.midX, y: rect.midY)
                turned.rotate(by: .degrees(-90))
                turned.draw(resolved, at: .zero, anchor: .center)
            } else {
                ctx.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            }
            break
        }
    }
}

extension ItemType {
    /// A soft color per kind of furniture, the same in every layout so
    /// pieces are easy to follow between options.
    var planColor: Color {
        switch self {
        case .sofa, .chair: return Color(light: 0x2F6B5B, dark: 0x7DBBA6)       // the accent green
        case .bed: return Color(light: 0x5B6FA8, dark: 0x9AAADB)                // dusty blue
        case .desk, .table: return Color(light: 0xA0703C, dark: 0xD7A673)       // warm wood
        case .dresser, .shelf: return Color(light: 0x7A6A8F, dark: 0xB5A6CA)    // muted plum
        case .tvStand: return Color(light: 0x55595E, dark: 0xA3A8AE)            // graphite
        case .lamp: return Color(light: 0xC09A2E, dark: 0xE6C25E)               // soft gold
        case .rug: return Color(light: 0xB0745F, dark: 0xD9A08B)                // terracotta
        case .other: return Color(light: 0x6C6B64, dark: 0x9D9B93)              // grey
        }
    }
}
