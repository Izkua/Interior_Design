import SwiftUI
import UIKit

/// A text field for a length. The value is a binding in centimeters; what
/// the person sees and types follows the chosen unit system. Bad input shows
/// a message and leaves the stored value unchanged.
///
/// By default the value updates while typing. Set `updatesWhileTyping` to
/// false to update only when the person taps Return or leaves the field,
/// for values where every in-between number would move something on screen.
struct LengthField: View {
    let title: String
    @Binding var cm: Double
    let unit: UnitSystem
    let range: ClosedRange<Double>
    var updatesWhileTyping = true
    /// Room walls or furniture; changes what a bare number means.
    var scale: LengthScale = .room

    @State private var text = ""
    @State private var errorMessage: String?
    /// The text this field last filled in itself. Anything different was
    /// typed by the person.
    @State private var shownText = ""
    /// True once the person has typed, so just tapping in and out of the
    /// field never re-saves the rounded display value.
    @State private var edited = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)

            TextField(scale.example(unit), text: $text)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { commit() }
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
            if focused && newValue != shownText {
                edited = true
                // Check as they type; save now only if updating live.
                if let value = validated(newValue), updatesWhileTyping {
                    cm = value
                }
            }
        }
        .onChange(of: cm) { _, _ in
            if !focused { refreshText() }
        }
        .onChange(of: unit) { _, _ in
            refreshText()
            errorMessage = nil
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
            // Select what is there, so typing a new size replaces it
            // instead of adding to "12′ 6″". Wait a moment for the focus
            // to settle, and only act for this field.
            DispatchQueue.main.async {
                guard focused, let field = note.object as? UITextField else { return }
                field.selectAll(nil)
            }
        }
    }

    private func refreshText() {
        shownText = Length.format(cm, system: unit, scale: scale)
        text = shownText
    }

    /// Saves what was typed if it is valid, then shows the stored value
    /// in the standard format.
    private func commit() {
        if edited, let value = validated(text), value != cm {
            cm = value
        }
        edited = false
        refreshText()
        errorMessage = nil
    }

    /// The typed length in centimeters, or nil (with a message) if it is
    /// not a usable length.
    private func validated(_ input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            errorMessage = "Enter a size, like \(scale.example(unit))"
            return nil
        }
        guard let value = Length.parse(trimmed, system: unit, scale: scale) else {
            errorMessage = "Try a size like \(scale.example(unit))"
            return nil
        }
        guard range.contains(value) else {
            let low = Length.format(range.lowerBound, system: unit, scale: scale)
            let high = Length.format(range.upperBound, system: unit, scale: scale)
            errorMessage = "Must be between \(low) and \(high)"
            return nil
        }
        errorMessage = nil
        return value
    }
}
