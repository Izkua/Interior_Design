import SwiftUI

/// A text field for a length. The value is a binding in centimeters; what
/// the person sees and types follows the chosen unit system. Bad input shows
/// a message and leaves the stored value unchanged.
struct LengthField: View {
    let title: String
    @Binding var cm: Double
    let unit: UnitSystem
    let range: ClosedRange<Double>

    @State private var text = ""
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)

            TextField(unit.example, text: $text)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .font(Typography.headline)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(
                    Theme.surfaceAlt,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(errorMessage == nil ? Color.clear : Theme.danger, lineWidth: 1.5)
                )
                .accessibilityLabel(title)

            if let errorMessage {
                Text(errorMessage)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { refreshText() }
        .onChange(of: text) { _, newValue in
            if focused { apply(newValue) }
        }
        .onChange(of: cm) { _, _ in
            if !focused { refreshText() }
        }
        .onChange(of: unit) { _, _ in
            refreshText()
            errorMessage = nil
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused {
                refreshText()
                errorMessage = nil
            }
        }
    }

    private func refreshText() {
        text = Length.format(cm, system: unit)
    }

    private func apply(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            errorMessage = "Enter a size, like \(unit.example)"
            return
        }
        guard let value = Length.parse(trimmed, system: unit) else {
            errorMessage = "Try a size like \(unit.example)"
            return
        }
        guard range.contains(value) else {
            let low = Length.format(range.lowerBound, system: unit)
            let high = Length.format(range.upperBound, system: unit)
            errorMessage = "Must be between \(low) and \(high)"
            return
        }
        errorMessage = nil
        cm = value
    }
}
