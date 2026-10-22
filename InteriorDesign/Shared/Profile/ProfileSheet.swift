import SwiftUI
import SwiftData

/// Profile sheet, guest state only for now. Sign-in comes in a later week.
/// The preferences here are saved on the device.
struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue
    @AppStorage(SettingsKey.defaultBudget) private var defaultBudget: Double?
    @AppStorage(SettingsKey.preferredStyles) private var stylesCSV = ""
    @AppStorage(SettingsKey.preferredMaterials) private var materialsCSV = ""
    @AppStorage(SettingsKey.minimumRating) private var minimumRating: Double = 0

    @State private var showSignInNote = false

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var selectedStyles: Set<String> {
        Set(stylesCSV.split(separator: ",").map(String.init))
    }

    private var selectedMaterials: Set<String> {
        Set(materialsCSV.split(separator: ",").map(String.init))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    guestCard
                    preferencesCard
                    #if DEBUG
                    debugCard
                    #endif
                }
                .padding(Theme.Space.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .frame(minHeight: Theme.minTap)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Guest header

    private var guestCard: some View {
        AppCard {
            VStack(spacing: Theme.Space.md) {
                Image(systemName: "person.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 80, height: 80)
                    .background(Theme.accent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(spacing: Theme.Space.xs) {
                    Text("Guest")
                        .font(Typography.title)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Your rooms and items are saved on this phone.")
                        .font(Typography.body)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                PrimaryButton(title: "Sign in or create account") {
                    showSignInNote = true
                }

                if showSignInNote {
                    Text("Accounts are coming in a later update. Everything works as a guest in the meantime.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Preferences

    private var preferencesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SectionHeader(title: "Preferences")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Units")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Picker("Units", selection: $unitRaw) {
                        ForEach(UnitSystem.allCases) { system in
                            Text(system.title).tag(system.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Default budget")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                    TextField(
                        "Optional",
                        value: $defaultBudget,
                        format: .currency(code: currencyCode)
                    )
                    .keyboardType(.decimalPad)
                    .font(Typography.headline)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 48)
                    .background(
                        Theme.surfaceAlt,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    )
                    Text("The starting budget when you shop for a room.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Styles you like")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                    FlowLayout(spacing: Theme.Space.sm) {
                        ForEach(StyleOption.all, id: \.self) { style in
                            Chip(title: style, isSelected: selectedStyles.contains(style)) {
                                stylesCSV = toggled(style, in: stylesCSV, options: StyleOption.all)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Materials you like")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                    FlowLayout(spacing: Theme.Space.sm) {
                        ForEach(MaterialOption.all, id: \.self) { material in
                            Chip(title: material, isSelected: selectedMaterials.contains(material)) {
                                materialsCSV = toggled(material, in: materialsCSV, options: MaterialOption.all)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Minimum star rating")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Picker("Minimum star rating", selection: $minimumRating) {
                        ForEach(RatingOption.all, id: \.self) { rating in
                            Text(RatingOption.title(rating)).tag(rating)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    /// The comma-separated list with `option` added or removed, kept in
    /// the same order as `options` so the stored text does not shuffle.
    private func toggled(_ option: String, in csv: String, options: [String]) -> String {
        var current = Set(csv.split(separator: ",").map(String.init))
        if current.contains(option) {
            current.remove(option)
        } else {
            current.insert(option)
        }
        return options.filter { current.contains($0) }.joined(separator: ",")
    }

    // MARK: Debug

    #if DEBUG
    private var debugCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionHeader(title: "Developer")
                Text("Only in debug builds.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                PrimaryButton(title: "Load sample data", style: .tinted) {
                    SeedData.insertSamples(context)
                }
            }
        }
    }
    #endif
}
