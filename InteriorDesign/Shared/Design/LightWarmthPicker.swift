import SwiftUI

/// Picks how warm or cool a light is: Not sure, Warm, Neutral, or Cool.
struct LightWarmthPicker: View {
    var title: String
    @Binding var selection: LightWarmth?
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.headline)
                .foregroundStyle(Theme.textPrimary)
            Picker(title, selection: $selection) {
                Text("Not sure").tag(LightWarmth?.none)
                ForEach(LightWarmth.allCases) { warmth in
                    Text(warmth.title).tag(Optional(warmth))
                }
            }
            .pickerStyle(.segmented)
            Text(selection?.detail ?? help ?? "")
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
