import SwiftUI
import UIKit

/// Sign in or create an account. Optional: everything works as a guest.
struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthStore.shared

    private enum Mode: String, CaseIterable {
        case signIn = "Sign in"
        case signUp = "Create account"
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.md) {
                Text("Save your preferences to an account. Your rooms and items stay on this phone either way.")
                    .font(Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                providerButtons

                HStack {
                    Rectangle().fill(Theme.line).frame(height: 1)
                    Text("or with email").font(Typography.caption).foregroundStyle(Theme.textSecondary)
                    Rectangle().fill(Theme.line).frame(height: 1)
                }

                AppCard {
                    VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                        Picker("Mode", selection: $mode) {
                            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        field("Email") {
                            TextField("you@example.com", text: $email)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: .email)
                                .submitLabel(.next)
                                .onSubmit { focus = .password }
                        }
                        field("Password") {
                            SecureField(mode == .signUp ? "At least 8 characters" : "Password", text: $password)
                                .textContentType(mode == .signUp ? .newPassword : .password)
                                .focused($focus, equals: .password)
                                .submitLabel(.go)
                                .onSubmit(submit)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(Typography.caption)
                                .foregroundStyle(Theme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let notice {
                            Text(notice)
                                .font(Typography.caption)
                                .foregroundStyle(Theme.accent)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        PrimaryButton(title: isWorking ? "Please wait…" : mode.rawValue, action: submit)
                            .disabled(isWorking || !canSubmit)
                            .opacity(canSubmit ? 1 : 0.5)

                        if mode == .signIn {
                            Button("Forgot password?", action: forgotPassword)
                                .font(Typography.subheadline)
                                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                                .disabled(isWorking)
                        }
                    }
                }
            }
            .padding(Theme.Space.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(mode.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: mode) { _, _ in
            errorMessage = nil
        }
    }

    // MARK: Google and Apple

    /// Same size and prominence for both, as Apple asks.
    private var providerButtons: some View {
        VStack(spacing: Theme.Space.sm) {
            providerButton("Continue with Apple", symbol: "apple.logo", enabled: BackendConfig.appleSignInEnabled, provider: "apple")
            providerButton("Continue with Google", symbol: "g.circle", enabled: BackendConfig.googleSignInEnabled, provider: "google")
            if !BackendConfig.appleSignInEnabled || !BackendConfig.googleSignInEnabled {
                Text("Apple and Google sign-in are coming soon. Email works now.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func providerButton(_ title: String, symbol: String, enabled: Bool, provider: String) -> some View {
        Button {
            Task { await signIn(with: provider) }
        } label: {
            Label(title, systemImage: symbol)
                .font(Typography.headline)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous).strokeBorder(Theme.line))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled || isWorking)
        .opacity(enabled ? 1 : 0.45)
    }

    // MARK: Actions

    private var canSubmit: Bool {
        email.contains("@") && password.count >= (mode == .signUp ? 8 : 1)
    }

    private func submit() {
        guard canSubmit, !isWorking else { return }
        Task {
            await run {
                switch mode {
                case .signIn:
                    try await auth.signIn(email: email, password: password)
                    dismiss()
                case .signUp:
                    try await auth.signUp(email: email, password: password)
                    mode = .signIn
                    notice = "Check your email for a link to confirm your account, then sign in."
                }
            }
        }
    }

    private func forgotPassword() {
        guard email.contains("@") else {
            errorMessage = "Type your email above first."
            return
        }
        Task {
            await run {
                try await auth.resetPassword(email: email)
                notice = "If there's an account for \(email), a reset link is on its way."
            }
        }
    }

    private func signIn(with provider: String) async {
        guard let anchor = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        await run {
            try await auth.signIn(with: provider, from: anchor)
            dismiss()
        }
    }

    /// Shows a spinner while working and a plain message if it fails.
    private func run(_ work: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        notice = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Typography.caption).foregroundStyle(Theme.textSecondary)
            content()
                .font(Typography.headline)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        }
    }
}
