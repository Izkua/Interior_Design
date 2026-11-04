import Foundation
import CryptoKit
import AuthenticationServices

/// Helpers for native Sign in with Apple (the system sheet, no browser).
///
/// How it works: the app makes a random "nonce", gives Apple its SHA-256
/// hash, and Apple puts that hash inside the signed identity token. The app
/// then sends Supabase the token plus the original nonce; Supabase checks
/// they match, so a stolen token can't be replayed.
enum AppleSignIn {
    /// A random string, used once.
    static func makeNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters.randomElement(using: &generator)! })
    }

    /// The SHA-256 hash of the nonce, as lowercase hex (what Apple expects).
    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Asks for the person's name and email. Apple only shares them the
    /// first time someone signs in to the app.
    static func configure(_ request: ASAuthorizationAppleIDRequest, nonce: String) {
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    /// "Ada Lovelace" from the name parts Apple shares, or nil.
    static func displayName(_ name: PersonNameComponents?) -> String? {
        guard let name else { return nil }
        let text = PersonNameComponentsFormatter.localizedString(from: name, style: .default)
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// The parts of a finished Apple sign-in that the app needs.
    struct Result: Sendable {
        var identityToken: String
        var nonce: String
        var name: String?
    }

    /// Reads the result of the system sheet. Cancelling throws
    /// `AuthError.cancelled`, which the screen ignores quietly.
    static func result(from outcome: Swift.Result<ASAuthorization, Error>, nonce: String) throws -> Result {
        switch outcome {
        case .failure(let error):
            if let code = (error as? ASAuthorizationError)?.code, code == .canceled || code == .unknown {
                throw AuthError.cancelled
            }
            throw AuthError.server("Sign in with Apple didn't finish. Please try again.")
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                throw AuthError.server("Apple didn't send a sign-in token. Please try again.")
            }
            return Result(identityToken: token, nonce: nonce, name: displayName(credential.fullName))
        }
    }
}
