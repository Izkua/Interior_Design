import SwiftUI
import UIKit

/// A top-down skeleton of a layout: the room, its doors and windows, and
/// each item as a soft colored box with its name. A thicker edge marks the
/// item's front. Pieces too small for their name get a numbered badge, and
/// a legend along the bottom says what each number is.
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
    /// Callers that pass one should make it with `fit(_:_:size:)`.
    var space: CanvasSpace? = nil

    static let padding: CGFloat = 36
    /// Room kept under the plan for the legend, when there is one.
    static let legendHeight: CGFloat = 26

    /// Fits the room to `size`, leaving a strip at the bottom for the
    /// legend if any piece ends up with a badge.
    static func fit(_ room: LayoutRoom, _ placed: [PlacedItem], size: CGSize) -> CanvasSpace {
        let full = CanvasSpace(corners: room.corners, size: size, padding: padding)
        guard PlanLabels.badged(placed, scale: full.scale).isEmpty == false else { return full }
        let shorter = CGSize(width: size.width, height: max(size.height - legendHeight, 1))
        return CanvasSpace(corners: room.corners, size: shorter, padding: padding)
    }

    var body: some View {
        GeometryReader { geo in
            let space = self.space ?? Self.fit(room, placed, size: geo.size)
            let order = Self.drawOrder(placed)
            let badged = PlanLabels.badged(order, scale: space.scale)
            ZStack(alignment: .bottomLeading) {
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
                    for item in order {
                        LayoutPlanPainter.draw(
                            &context,
                            item,
                            space: space,
                            selected: item.item.id == selectedID,
                            problem: problemIDs.contains(item.item.id)
                        )
                    }
                    // Names last, so no box is drawn over a label.
                    for item in order {
                        LayoutPlanPainter.drawLabel(&context, item, space: space, badge: badged.firstIndex { $0.item.id == item.item.id }.map { $0 + 1 })
                    }
                }
                if !badged.isEmpty {
                    legend(badged)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Floor plan with \(placed.map(\.item.name).joined(separator: ", "))")
    }

    /// Rugs first, so everything else sits on top of them.
    private static func drawOrder(_ placed: [PlacedItem]) -> [PlacedItem] {
        placed.sorted { $0.item.liesFlat && !$1.item.liesFlat }
    }

    private func legend(_ badged: [PlacedItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm + 4) {
                ForEach(Array(badged.enumerated()), id: \.element.item.id) { index, item in
                    HStack(spacing: Theme.Space.xs) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: PlanLabels.badgeSize, height: PlanLabels.badgeSize)
                            .background(Circle().fill(Theme.surface))
                            .overlay(Circle().stroke(item.item.type.planColor, lineWidth: 1.5))
                        Text(item.item.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.sm + 4)
        }
        .frame(height: Self.legendHeight)
        .padding(.bottom, Theme.Space.xs)
    }
}

/// What goes on each piece: its name when it fits, otherwise a badge.
/// Kept apart from the drawing so it can be tested.
enum PlanLabels {
    enum Label: Equatable {
        case text(String, sideways: Bool)
        case badge
    }

    static let fontSize: CGFloat = 10
    static let badgeSize: CGFloat = 18
    /// Space kept clear between a label and the edge of its box.
    static let inset: CGFloat = 6
    /// Height of one line of label text.
    static let lineHeight: CGFloat = 13

    /// The full name if it fits, then the kind of item ("Lamp", "Shelf"),
    /// then a badge. Tall, thin boxes may write the name sideways.
    static func choose(name: String, typeName: String, width: CGFloat, height: CGFloat, measure: (String) -> CGFloat) -> Label {
        let options = name == typeName ? [name] : [name, typeName]
        for option in options {
            let length = measure(option)
            if length <= width - inset && lineHeight <= height - inset / 2 {
                return .text(option, sideways: false)
            }
            if height > width * 1.4 && length <= height - inset && lineHeight <= width - inset / 2 {
                return .text(option, sideways: true)
            }
        }
        return .badge
    }

    static func label(for item: PlacedItem, scale: CGFloat) -> Label {
        let box = item.footprint
        return choose(
            name: item.item.name,
            typeName: item.item.type.displayName,
            width: CGFloat(box.maxX - box.minX) * scale,
            height: CGFloat(box.maxY - box.minY) * scale,
            measure: measure
        )
    }

    /// The pieces that get a badge, in the order they are numbered.
    static func badged(_ placed: [PlacedItem], scale: CGFloat) -> [PlacedItem] {
        placed.filter { label(for: $0, scale: scale) == .badge }
    }

    static let font = Font.system(size: fontSize, weight: .semibold)
    private static let uiFont = UIFont.systemFont(ofSize: fontSize, weight: .semibold)

    static func measure(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: uiFont]).width)
    }
}

enum LayoutPlanPainter {
    static func rect(_ item: PlacedItem, space: CanvasSpace) -> CGRect {
        let box = item.footprint
        let topLeft = space.viewPoint(Point2D(x: box.minX, y: box.minY))
        let bottomRight = space.viewPoint(Point2D(x: box.maxX, y: box.maxY))
        return CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
    }

    static func draw(_ ctx: inout GraphicsContext, _ item: PlacedItem, space: CanvasSpace, selected: Bool, problem: Bool) {
        let rect = rect(item, space: space)
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
    }

    /// The item's name, or its numbered badge when `badge` is set. A rug's
    /// name sits near its top edge so the table on it doesn't hide it.
    static func drawLabel(_ ctx: inout GraphicsContext, _ item: PlacedItem, space: CanvasSpace, badge: Int?) {
        let rect = rect(item, space: space)
        let center = CGPoint(x: rect.midX, y: rect.midY)

        if let badge {
            let size = PlanLabels.badgeSize
            let circle = Path(ellipseIn: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size))
            ctx.fill(circle, with: .color(Theme.surface))
            ctx.stroke(circle, with: .color(item.item.type.planColor), lineWidth: 1.5)
            let number = ctx.resolve(Text("\(badge)").font(.system(size: 10, weight: .bold)).foregroundColor(Theme.textPrimary))
            ctx.draw(number, at: center, anchor: .center)
            return
        }

        guard case let .text(name, sideways) = PlanLabels.label(for: item, scale: space.scale) else { return }
        let text = ctx.resolve(Text(name).font(PlanLabels.font).foregroundColor(Theme.textPrimary))
        if sideways {
            var turned = ctx
            turned.translateBy(x: center.x, y: center.y)
            turned.rotate(by: .degrees(-90))
            turned.draw(text, at: .zero, anchor: .center)
        } else if item.item.liesFlat {
            ctx.draw(text, at: CGPoint(x: rect.midX, y: rect.minY + PlanLabels.inset), anchor: .top)
        } else {
            ctx.draw(text, at: center, anchor: .center)
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
