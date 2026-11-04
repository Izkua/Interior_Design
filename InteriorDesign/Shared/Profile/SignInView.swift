import SwiftUI
import UIKit
import AuthenticationServices

/// Sign in or create an account. Optional: everything works as a guest.
struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    /// The one-time code for the current Sign in with Apple attempt.
    @State private var appleNonce = ""
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
            if BackendConfig.appleSignInEnabled {
                appleButton
            } else {
                providerButton("Continue with Apple", symbol: "apple.logo", enabled: false, provider: "apple")
            }
            if BackendConfig.googleSignInEnabled {
                googleButton
            } else {
                providerButton("Continue with Google", symbol: "g.circle", enabled: false, provider: "google")
                Text("Google sign-in is coming soon.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// Apple's own button: black in light mode, white in dark mode.
    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            appleNonce = AppleSignIn.makeNonce()
            AppleSignIn.configure(request, nonce: appleNonce)
        } onCompletion: { outcome in
            Task {
                await run {
                    let result = try AppleSignIn.result(from: outcome, nonce: appleNonce)
                    try await auth.signIn(apple: result)
                    dismiss()
                }
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        .disabled(isWorking)
        // Changing style needs a fresh button.
        .id(colorScheme)
    }

    /// Google's "neutral" button style: white with a grey border in light
    /// mode, near-black in dark mode, same size as Apple's.
    private var googleButton: some View {
        let dark = colorScheme == .dark
        return Button {
            Task { await signIn(with: "google") }
        } label: {
            HStack(spacing: 10) {
                Text("G")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                    .accessibilityHidden(true)
                Text("Continue with Google")
                    .font(.system(size: 19, weight: .medium))
            }
            .foregroundStyle(dark ? Color(red: 0.89, green: 0.89, blue: 0.89) : Color(red: 0.12, green: 0.12, blue: 0.12))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(dark ? Color(red: 0.075, green: 0.075, blue: 0.08) : .white,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .strokeBorder(dark ? Color(red: 0.56, green: 0.57, blue: 0.56) : Color(red: 0.45, green: 0.47, blue: 0.46), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .disabled(isWorking)
        .accessibilityLabel("Continue with Google")
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
        } catch AuthError.cancelled {
            // Closed the Apple sheet: nothing to say.
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
