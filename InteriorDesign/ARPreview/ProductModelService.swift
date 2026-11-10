import Foundation

/// Gets an AI-made 3D model (GLB) of a catalog product from our backend
/// (the generate-3d Edge Function, which uses Stability AI's Stable Point
/// Aware 3D). Each product's model is made once and shared, and also kept on the
/// phone, so opening the same product again costs nothing.
enum ProductModelService {
    enum Failure: LocalizedError, Equatable {
        case notAvailable
        case signInNeeded
        case limitReached(String)
        case offline
        case failed

        var errorDescription: String? {
            switch self {
            case .notAvailable: return "AI 3D models aren't available yet."
            case .signInNeeded: return "Sign in to make an AI 3D model of this product."
            case .limitReached(let message): return message
            case .offline: return "You're offline, so the 3D model couldn't be made."
            case .failed: return "The 3D model couldn't be made this time."
            }
        }
    }

    /// The GLB file for a product: from the phone if it was fetched
    /// before, else from the backend (made there if it's the first time).
    static func model(productID: String) async throws -> Data {
        guard BackendConfig.productModelsEnabled else { throw Failure.notAvailable }
        guard let file = cacheFile(productID) else { throw Failure.failed }
        if let saved = try? Data(contentsOf: file) { return saved }

        var request = URLRequest(url: BackendConfig.functionsURL.appendingPathComponent("generate-3d"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(await AuthStore.shared.validAccessToken() ?? BackendConfig.publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue(DeviceID.current, forHTTPHeaderField: "x-device-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["productId": productID])

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.offline
        }
        struct Reply: Decodable { var url: URL?; var error: String? }
        let reply = try? JSONDecoder().decode(Reply.self, from: data)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200:
            guard let url = reply?.url else { throw Failure.failed }
            guard let (glb, fileResponse) = try? await URLSession.shared.data(from: url),
                  (fileResponse as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.failed }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? glb.write(to: file)
            return glb
        case 401: throw Failure.signInNeeded
        case 429, 503: throw Failure.limitReached(reply?.error ?? "You've reached the limit for 3D models for now.")
        case 404, 501: throw Failure.notAvailable
        default: throw Failure.failed
        }
    }

    /// Where a product's model is kept on the phone (the system may clear
    /// it when space runs low; it's fetched again for free).
    static func cacheFile(_ productID: String) -> URL? {
        guard productID.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil,
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return caches.appendingPathComponent("ProductModels/\(productID).glb")
    }
}
