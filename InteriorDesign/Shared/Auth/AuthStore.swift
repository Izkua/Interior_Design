import Foundation
import Observation
import AuthenticationServices

/// Who is signed in, if anyone. Signing in is optional: guests use every
/// feature that runs on the phone, and their rooms and items stay on the
/// phone either way. (So "guest to account" keeps everything: signing in
/// never touches the local data.)
@MainActor
@Observable
final class AuthStore {
    static let shared = AuthStore()

    private(set) var session: AuthSession?
    /// AI pictures made this month and today, shown on the profile and the
    /// Visualize screen. Only successful pictures count.
    private(set) var imagesThisMonth: Int?
    private(set) var imagesToday: Int?

    /// The limits, matching app_config on the backend.
    static let imagesPerDay = 3
    static let imagesPerMonth = 10

    var isSignedIn: Bool { session != nil }

    private let client: AuthClient
    private static let keychainKey = "auth.session"

    init(client: AuthClient = AuthClient()) {
        self.client = client
        if let data = Keychain.load(Self.keychainKey) {
            session = try? JSONDecoder().decode(AuthSession.self, from: data)
        }
    }

    // MARK: Signing in and out

    func signIn(email: String, password: String) async throws {
        store(try await client.signIn(email: Self.clean(email), password: password))
    }

    func signUp(email: String, password: String) async throws {
        try await client.signUp(email: Self.clean(email), password: password)
    }

    func resetPassword(email: String) async throws {
        try await client.resetPassword(email: Self.clean(email))
    }

    /// Google (and, later, Apple) sign-in in a secure browser sheet.
    func signIn(with provider: String, from anchor: ASPresentationAnchor) async throws {
        let url = client.authorizeURL(provider: provider)
        let callback = try await WebAuth.start(url: url, callbackScheme: BackendConfig.callbackScheme, anchor: anchor)
        store(try await client.session(fromCallback: callback))
    }

    /// Handles links that open the app, like the email confirmation.
    func handle(url: URL) async {
        guard url.scheme == BackendConfig.callbackScheme,
              let session = try? await client.session(fromCallback: url) else { return }
        store(session)
    }

    func signOut() async {
        if let token = session?.accessToken {
            await client.signOut(accessToken: token)
        }
        clear()
    }

    /// Deletes the account on the backend, then signs out. Rooms and items
    /// on this phone stay.
    func deleteAccount() async throws {
        guard let token = await validAccessToken() else { throw AuthError.server("Please sign in again first.") }
        var request = URLRequest(url: BackendConfig.functionsURL.appendingPathComponent("delete-account"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.offline
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            struct Body: Decodable { var error: String }
            let message = (try? JSONDecoder().decode(Body.self, from: data))?.error
            throw AuthError.server(message ?? "Couldn't delete the account. Please try again.")
        }
        clear()
    }

    // MARK: Tokens

    /// An access token that works right now, refreshing it if needed.
    /// Nil for guests, or if the session can't be renewed.
    func validAccessToken() async -> String? {
        guard let current = session else { return nil }
        guard current.needsRefresh else { return current.accessToken }
        do {
            let fresh = try await client.refresh(current.refreshToken)
            store(fresh)
            return fresh.accessToken
        } catch AuthError.offline {
            // Keep the session; try again when back online.
            return nil
        } catch {
            // The refresh token was revoked or expired: sign out.
            clear()
            return nil
        }
    }

    // MARK: Profile

    /// Reads how many AI pictures were made this month. Row level security
    /// means this only ever sees the signed-in person's rows.
    func loadUsage() async {
        guard let token = await validAccessToken() else { return }
        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = utc.date(from: utc.dateComponents([.year, .month], from: Date()))!
        var components = URLComponents(url: BackendConfig.restURL.appendingPathComponent("usage_events"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "created_at"),
            URLQueryItem(name: "kind", value: "eq.image"),
            URLQueryItem(name: "created_at", value: "gte.\(ISO8601DateFormatter().string(from: start))"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }
        imagesThisMonth = rows.count
        // "Today" uses the same UTC day as the backend's limit.
        let today = utc.startOfDay(for: Date())
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        imagesToday = rows.filter { row in
            guard let text = row["created_at"] as? String,
                  let date = parser.date(from: text) ?? ISO8601DateFormatter().date(from: text) else { return false }
            return date >= today
        }.count
    }

    /// Saves the person's shopping preferences to their profile, so they
    /// follow the account. Fails quietly offline; the phone keeps its copy.
    func syncPreferences(_ preferences: [String: Any], budget: Double?) async {
        guard let token = await validAccessToken(), let userID = session?.user.id else { return }
        var components = URLComponents(url: BackendConfig.restURL.appendingPathComponent("profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(userID)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["preferences": preferences, "updated_at": ISO8601DateFormatter().string(from: Date())]
        body["budget"] = budget ?? NSNull()
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: Helpers

    private func store(_ new: AuthSession) {
        session = new
        if let data = try? JSONEncoder().encode(new) {
            Keychain.save(data, for: Self.keychainKey)
        }
    }

    private func clear() {
        session = nil
        imagesThisMonth = nil
        imagesToday = nil
        Keychain.delete(Self.keychainKey)
    }

    private static func clean(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Runs a browser sign-in (Google, Apple) in Apple's secure sheet, which
/// shares nothing with the app and closes itself on the way back.
enum WebAuth {
    @MainActor
    static func start(url: URL, callbackScheme: String, anchor: ASPresentationAnchor) async throws -> URL {
        let provider = AnchorProvider(anchor: anchor)
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: AuthError.offline)
                }
            }
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = true
            session.start()
            // Keep the provider alive until the sheet closes.
            objc_setAssociatedObject(session, "provider", provider, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        let anchor: ASPresentationAnchor
        init(anchor: ASPresentationAnchor) { self.anchor = anchor }
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
    }
}
