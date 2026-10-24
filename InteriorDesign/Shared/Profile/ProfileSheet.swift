import SwiftUI
import SwiftData

/// The profile sheet: guest or signed in, and shopping preferences.
/// Preferences are saved on the phone, and also to the account when
/// signed in.
struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue
    @AppStorage(SettingsKey.defaultBudget) private var defaultBudget: Double?
    @AppStorage(SettingsKey.preferredStyles) private var stylesCSV = ""
    @AppStorage(SettingsKey.preferredMaterials) private var materialsCSV = ""
    @AppStorage(SettingsKey.minimumRating) private var minimumRating: Double = 0
    @AppStorage(SettingsKey.demoAIFeatures) private var demoAIFeatures = false

    @State private var auth = AuthStore.shared
    @State private var showSignIn = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var accountError: String?

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
                    if let session = auth.session {
                        accountCard(session.user)
                    } else {
                        guestCard
                    }
                    preferencesCard
                    #if DEBUG
                    debugCard
                    #endif
                }
                .padding(Theme.Space.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationDestination(isPresented: $showSignIn) { SignInView() }
            .task(id: auth.session?.user.id) { await auth.loadUsage() }
            .onChange(of: syncKey) { _, _ in syncPreferences() }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out") { Task { await auth.signOut() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your rooms and items stay on this phone.")
            }
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive, action: deleteAccount)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account, saved preferences, and usage. Your rooms and items stay on this phone. This can't be undone.")
            }
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
                    showSignIn = true
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Signed in

    private func accountCard(_ user: AuthUser) -> some View {
        AppCard {
            VStack(spacing: Theme.Space.md) {
                Text(initials(user))
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 80, height: 80)
                    .background(Theme.accent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(spacing: Theme.Space.xs) {
                    Text(user.name ?? user.email ?? "Signed in")
                        .font(Typography.title)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    if user.name != nil, let email = user.email {
                        Text(email)
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text("Signed in with \(providerName(user.provider))")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack {
                    Label("AI pictures this month", systemImage: "sparkles")
                        .font(Typography.subheadline)
                    Spacer()
                    Text(auth.imagesThisMonth.map { "\($0) of 10" } ?? "–")
                        .font(Typography.headline)
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(12)
                .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))

                PrimaryButton(title: "Sign out", style: .tinted) { confirmSignOut = true }

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Text(isDeleting ? "Deleting…" : "Delete account")
                        .font(Typography.subheadline)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                }
                .foregroundStyle(Theme.danger)
                .disabled(isDeleting)

                if let accountError {
                    Text(accountError)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func initials(_ user: AuthUser) -> String {
        let source = user.name ?? user.email ?? "?"
        let words = source.split(whereSeparator: { $0 == " " || $0 == "@" || $0 == "." })
        return words.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }

    private func providerName(_ provider: String) -> String {
        switch provider {
        case "google": return "Google"
        case "apple": return "Apple"
        default: return "email"
        }
    }

    private func deleteAccount() {
        isDeleting = true
        accountError = nil
        Task {
            do {
                try await auth.deleteAccount()
            } catch let error as AuthError {
                accountError = error.errorDescription
            } catch {
                accountError = "Couldn't delete the account. Please try again."
            }
            isDeleting = false
        }
    }

    /// Changes whenever a preference changes.
    private var syncKey: String {
        "\(unitRaw)|\(defaultBudget ?? -1)|\(stylesCSV)|\(materialsCSV)|\(minimumRating)"
    }

    /// Copies the preferences to the account, when signed in.
    private func syncPreferences() {
        guard auth.isSignedIn else { return }
        let preferences: [String: Any] = [
            "units": unitRaw,
            "styles": stylesCSV.split(separator: ",").map(String.init),
            "materials": materialsCSV.split(separator: ",").map(String.init),
            "minimumRating": minimumRating,
        ]
        let budget = defaultBudget
        Task { await auth.syncPreferences(preferences, budget: budget) }
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
                Toggle("Demo AI features (made-up results)", isOn: $demoAIFeatures)
                    .font(Typography.subheadline)
                    .tint(Theme.accent)
            }
        }
    }
    #endif
}
