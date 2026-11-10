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

    /// A product's model that was already made (by anyone): from the
    /// phone, else the shared copy on the backend. Free; never makes a new
    /// one. Nil if there isn't one yet.
    static func savedModel(productID: String) async -> Data? {
        try? await model(productID: productID, cachedOnly: true)
    }

    /// The GLB file for a product: from the phone if it was fetched
    /// before, else from the backend. With `cachedOnly`, nothing new is
    /// made (nil if none exists yet).
    static func model(productID: String, cachedOnly: Bool = false) async throws -> Data? {
        guard BackendConfig.productModelsEnabled else { throw Failure.notAvailable }
        guard let file = await cacheFile(productID) else { throw Failure.failed }
        if let saved = try? Data(contentsOf: file) { return saved }

        var request = URLRequest(url: BackendConfig.functionsURL.appendingPathComponent("generate-3d"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(await AuthStore.shared.validAccessToken() ?? BackendConfig.publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue(DeviceID.current, forHTTPHeaderField: "x-device-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable { var productId: String; var cachedOnly: Bool }
        request.httpBody = try JSONEncoder().encode(Body(productId: productID, cachedOnly: cachedOnly))

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
            guard let url = reply?.url else {
                if cachedOnly { return nil }
                throw Failure.failed
            }
            guard let (glb, fileResponse) = try? await URLSession.shared.data(from: url),
                  (fileResponse as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.failed }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? glb.write(to: file)
            return glb
        case 401: throw Failure.signInNeeded
        case 422: throw Failure.limitReached(reply?.error ?? "The 3D model couldn't be made from this picture.")
        case 429, 503: throw Failure.limitReached(reply?.error ?? "You've reached the limit for 3D models for now.")
        case 404, 501: throw Failure.notAvailable
        default: throw Failure.failed
        }
    }

    /// Makes an AI 3D model (GLB) of the person's own piece from its
    /// cutout. The photo goes to our backend and on to Stability AI to make
    /// the model; neither is stored there. Needs sign-in; counts toward
    /// the same daily and monthly limits as product models.
    static func model(fromPhoto png: Data) async throws -> Data {
        guard BackendConfig.productModelsEnabled else { throw Failure.notAvailable }
        guard let token = await AuthStore.shared.validAccessToken() else { throw Failure.signInNeeded }
        var request = URLRequest(url: BackendConfig.functionsURL.appendingPathComponent("generate-3d"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(DeviceID.current, forHTTPHeaderField: "x-device-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["photo": png.base64EncodedString()])

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.offline
        }
        struct Reply: Decodable { var glb: String?; var error: String? }
        let reply = try? JSONDecoder().decode(Reply.self, from: data)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200:
            guard let base64 = reply?.glb, let glb = Data(base64Encoded: base64), GLBModel.isGLB(glb) else { throw Failure.failed }
            return glb
        case 401: throw Failure.signInNeeded
        case 422: throw Failure.limitReached(reply?.error ?? "The 3D model couldn't be made from this picture.")
        case 429, 503: throw Failure.limitReached(reply?.error ?? "You've reached the limit for 3D models for now.")
        case 404, 501: throw Failure.notAvailable
        default: throw Failure.failed
        }
    }

    /// Where a product's model is kept on the phone (listed under the
    /// Catalog's 3D models button).
    @MainActor
    static func cacheFile(_ productID: String) -> URL? {
        SavedModels.shared.modelFile(productID)
    }
}
