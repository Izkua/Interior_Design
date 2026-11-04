import Foundation
import CryptoKit

/// A signed-in session from Supabase Auth.
struct AuthSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    /// When the access token stops working.
    var expiresAt: Date
    var user: AuthUser

    /// Refresh a minute early, so a request never goes out with a token
    /// that expires on the way.
    var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

struct AuthUser: Codable, Equatable, Sendable {
    var id: String
    var email: String?
    var name: String?
    /// "email", "google", or "apple".
    var provider: String
}

/// What can go wrong when signing in, in words a person understands.
enum AuthError: LocalizedError, Equatable {
    case wrongPassword
    case emailInUse
    case emailNotConfirmed
    case weakPassword(String)
    case invalidEmail
    case offline
    case rateLimited
    case cancelled
    case server(String)

    var errorDescription: String? {
        switch self {
        case .wrongPassword: return "That email and password don't match."
        case .emailInUse: return "There's already an account with that email. Try signing in."
        case .emailNotConfirmed: return "Please confirm your email first. Check your inbox for the link."
        case .weakPassword(let detail): return detail.isEmpty ? "Please choose a longer password (at least 8 characters)." : detail
        case .invalidEmail: return "That doesn't look like an email address."
        case .offline: return "You're offline. Your rooms and items still work; try signing in later."
        case .rateLimited: return "Too many tries. Please wait a minute."
        case .cancelled: return nil
        case .server(let message): return message
        }
    }
}

/// Talks to Supabase Auth over plain HTTPS. Only the publishable key is
/// used; passwords go straight to Supabase and are never stored by us.
struct AuthClient: Sendable {
    var session: URLSession = .shared

    // MARK: Email and password

    /// Creates an account. Supabase emails a confirmation link; the person
    /// can sign in after tapping it.
    func signUp(email: String, password: String) async throws {
        _ = try await post("signup", body: [
            "email": email,
            "password": password,
        ], query: ["redirect_to": BackendConfig.callbackURL.absoluteString])
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let data = try await post("token", body: ["email": email, "password": password], query: ["grant_type": "password"])
        return try Self.decodeSession(data)
    }

    /// Emails a reset link. Always "succeeds", so nobody can use it to find
    /// out which emails have accounts.
    func resetPassword(email: String) async throws {
        _ = try await post("recover", body: ["email": email], query: ["redirect_to": BackendConfig.callbackURL.absoluteString])
    }

    /// A fresh access token from the long-lived refresh token.
    func refresh(_ refreshToken: String) async throws -> AuthSession {
        let data = try await post("token", body: ["refresh_token": refreshToken], query: ["grant_type": "refresh_token"])
        return try Self.decodeSession(data)
    }

    func signOut(accessToken: String) async {
        _ = try? await post("logout", body: [:], bearer: accessToken)
    }

    /// Sets a new password, for the reset-password link.
    func updatePassword(_ password: String, accessToken: String) async throws {
        _ = try await send("user", method: "PUT", body: ["password": password], bearer: accessToken)
    }

    // MARK: Sign in with Apple (native)

    /// The request that trades Apple's identity token for a Supabase
    /// session. Kept separate so it can be tested.
    static func idTokenBody(provider: String, idToken: String, nonce: String) -> [String: String] {
        ["provider": provider, "id_token": idToken, "nonce": nonce]
    }

    func signIn(apple result: AppleSignIn.Result) async throws -> AuthSession {
        let data = try await post(
            "token",
            body: Self.idTokenBody(provider: "apple", idToken: result.identityToken, nonce: result.nonce),
            query: ["grant_type": "id_token"]
        )
        return try Self.decodeSession(data)
    }

    /// Saves a name to the account (Apple only shares it once).
    func saveName(_ name: String, accessToken: String) async throws {
        _ = try await send("user", method: "PUT", body: NameUpdate(data: .init(full_name: name)), bearer: accessToken)
    }

    private struct NameUpdate: Encodable {
        struct Fields: Encodable { var full_name: String }
        var data: Fields
    }

    // MARK: Google (browser sign-in with PKCE)

    /// PKCE ("pixie"): the app makes a secret `verifier` and sends only its
    /// hash (the `challenge`) when sign-in starts. Google and Supabase send
    /// back a one-time code, and only the app holding the verifier can
    /// trade it for a session. So a code caught on the way is useless.
    struct PKCE: Equatable, Sendable {
        var verifier: String
        var challenge: String

        static func make() -> PKCE {
            var bytes = [UInt8](repeating: 0, count: 32)
            var generator = SystemRandomNumberGenerator()
            for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255, using: &generator) }
            let verifier = base64URL(Data(bytes))
            return PKCE(verifier: verifier, challenge: challenge(for: verifier))
        }

        /// base64url(SHA-256(verifier)), without "=" padding.
        static func challenge(for verifier: String) -> String {
            base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        }

        static func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
    }

    /// The page that starts Google sign-in in a browser sheet. Supabase
    /// sends the person back to `callbackURL` with a one-time `code`.
    func authorizeURL(provider: String, pkce: PKCE) -> URL {
        var components = URLComponents(url: BackendConfig.authURL.appendingPathComponent("authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: BackendConfig.callbackURL.absoluteString),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        return components.url!
    }

    /// The one-time code in interiordesign://auth-callback?code=...
    /// Throws the provider's message if sign-in was refused.
    static func code(fromCallback url: URL) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let fragmentItems = URLComponents(string: "x:?" + (url.fragment ?? ""))?.queryItems ?? []
        let all = items + fragmentItems
        if let message = all.first(where: { $0.name == "error_description" })?.value {
            throw AuthError.server(message.replacingOccurrences(of: "+", with: " "))
        }
        guard let code = all.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw AuthError.server("Sign-in didn't finish. Please try again.")
        }
        return code
    }

    /// Trades the one-time code (plus the verifier) for a session.
    func session(code: String, verifier: String) async throws -> AuthSession {
        let data = try await post("token", body: ["auth_code": code, "code_verifier": verifier], query: ["grant_type": "pkce"])
        return try Self.decodeSession(data)
    }

    /// Reads the session out of the callback address
    /// (interiordesign://auth-callback#access_token=...&refresh_token=...).
    func session(fromCallback url: URL) async throws -> AuthSession {
        let fragment = url.fragment ?? url.query ?? ""
        var values: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { values[parts[0]] = parts[1].removingPercentEncoding }
        }
        if let message = values["error_description"] {
            throw AuthError.server(message.replacingOccurrences(of: "+", with: " "))
        }
        guard let access = values["access_token"], let refresh = values["refresh_token"] else {
            throw AuthError.server("Sign-in didn't finish. Please try again.")
        }
        let expiresIn = Double(values["expires_in"] ?? "") ?? 3600
        let user = try await currentUser(accessToken: access)
        return AuthSession(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expiresIn), user: user)
    }

    func currentUser(accessToken: String) async throws -> AuthUser {
        let data = try await send("user", method: "GET", body: nil, bearer: accessToken)
        let raw = try JSONDecoder().decode(RawUser.self, from: data)
        return raw.user
    }

    // MARK: Plumbing

    private func post(_ path: String, body: [String: String], query: [String: String] = [:], bearer: String? = nil) async throws -> Data {
        try await send(path, method: "POST", body: body, query: query, bearer: bearer)
    }

    private func send(_ path: String, method: String, body: (any Encodable)?, query: [String: String] = [:], bearer: String? = nil) async throws -> Data {
        var components = URLComponents(url: BackendConfig.authURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder().encode(body) }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Self.mapError(status: status, data: data)
        }
        return data
    }

    /// Turns Supabase's error answers into `AuthError`.
    static func mapError(status: Int, data: Data) -> AuthError {
        struct Body: Decodable {
            var error_code: String?
            var code: String?
            var msg: String?
            var message: String?
            var error_description: String?
        }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        let code = body?.error_code ?? body?.code ?? ""
        let message = body?.msg ?? body?.message ?? body?.error_description ?? ""
        switch code {
        case "invalid_credentials": return .wrongPassword
        case "user_already_exists", "email_exists": return .emailInUse
        case "email_not_confirmed": return .emailNotConfirmed
        case "weak_password": return .weakPassword(message)
        case "email_address_invalid", "validation_failed": return .invalidEmail
        case "over_request_rate_limit", "over_email_send_rate_limit": return .rateLimited
        default:
            if status == 429 { return .rateLimited }
            if status == 400, message.lowercased().contains("invalid login") { return .wrongPassword }
            return .server(message.isEmpty ? "Something went wrong (\(status)). Please try again." : message)
        }
    }

    static func decodeSession(_ data: Data) throws -> AuthSession {
        struct Raw: Decodable {
            var access_token: String
            var refresh_token: String
            var expires_in: Double
            var user: RawUser
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        return AuthSession(
            accessToken: raw.access_token,
            refreshToken: raw.refresh_token,
            expiresAt: Date().addingTimeInterval(raw.expires_in),
            user: raw.user.user
        )
    }

    /// The parts of Supabase's user object we use.
    private struct RawUser: Decodable {
        var id: String
        var email: String?
        var user_metadata: [String: JSONValue]?
        var app_metadata: [String: JSONValue]?

        var user: AuthUser {
            AuthUser(
                id: id,
                email: email,
                name: user_metadata?["full_name"]?.string ?? user_metadata?["name"]?.string,
                provider: app_metadata?["provider"]?.string ?? "email"
            )
        }
    }
}

/// Just enough JSON to read text values out of Supabase's metadata.
enum JSONValue: Decodable, Sendable {
    case string(String)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .string(text)
        } else {
            self = .other
        }
    }

    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}
