import SwiftUI

// MARK: - Button press style

/// Subtle scale-and-fade on press, used by every custom button. With
/// Reduce Motion on, it only fades.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Primary button

struct PrimaryButton: View {
    enum Style {
        case filled
        case tinted
    }

    let title: String
    var systemImage: String? = nil
    var style: Style = .filled
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(Typography.headline)
            .foregroundStyle(style == .filled ? Theme.onAccent : Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                style == .filled ? Theme.accent : Theme.accent.opacity(0.12),
                in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
            )
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Card

struct AppCard<Content: View>: View {
    var padding: CGFloat = Theme.Space.md
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Theme.surface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
    }
}

// MARK: - Icon buttons

/// Round icon button for use inside content (not in a toolbar).
struct IconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: Theme.minTap, height: Theme.minTap)
                .background(Theme.surfaceAlt, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Plain icon for navigation bars. The system draws the bar-button
/// background itself on newer iOS versions, so this adds none.
struct ToolbarIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .frame(width: Theme.minTap, height: Theme.minTap)
                .contentShape(Rectangle())
        }
        .foregroundStyle(Theme.textPrimary)
        .accessibilityLabel(label)
    }
}

// MARK: - Empty state

struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(Theme.accent)
                .frame(width: 72, height: 72)
                .background(Theme.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            Text(title)
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, action: action)
                    .frame(maxWidth: 280)
                    .padding(.top, Theme.Space.sm)
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At the largest text sizes the title and button go on two lines
        // instead of squeezing each other.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout())
        layout {
            Text(title)
                .font(Typography.headline)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if !typeSize.isAccessibilitySize { Spacer() }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Typography.subheadline)
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: Theme.minTap)
            }
        }
    }
}

// MARK: - Chip and tag

/// Tappable pill, used for choices (styles, add-a-door, and so on).
struct Chip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(Typography.subheadline)
            .foregroundStyle(isSelected ? Theme.onAccent : Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: Theme.minTap)
            .background(
                isSelected ? Theme.accent : Theme.surfaceAlt,
                in: Capsule()
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Small read-only label, for example "Estimated".
struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.surfaceAlt, in: Capsule())
    }
}

// MARK: - Wrapping layout

/// Lays children out left to right and wraps to a new line when full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return CGSize(width: usedWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
