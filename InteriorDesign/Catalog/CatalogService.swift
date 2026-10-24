import Foundation

/// Somewhere products come from. The app talks to this, not to a specific
/// source, so the backend and the bundled list are interchangeable.
protocol CatalogService: Sendable {
    func search(_ query: CatalogQuery) async throws -> [CatalogProduct]
}

/// Where a batch of results came from, to tell the person honestly.
enum CatalogSource: Equatable, Sendable {
    case live
    /// The bundled list, because the live catalog was unreachable.
    case curated
}

enum CatalogError: Error, LocalizedError {
    case offline
    case badResponse(Int)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .offline: return "You're offline."
        case .badResponse(let code): return "The catalog didn't answer properly (\(code))."
        case .rateLimited: return "Too many searches for now. Try again in a minute."
        }
    }
}

// MARK: - Live catalog (through our backend)

/// Searches through our Supabase Edge Function. The function holds the
/// catalog API key; the app never sees it.
struct BackendCatalogService: CatalogService {
    /// The signed-in person's token, if any. Guests search with the
    /// publishable key and a per-device limit.
    var accessToken: @Sendable () async -> String? = { nil }
    var session: URLSession = .shared

    func search(_ query: CatalogQuery) async throws -> [CatalogProduct] {
        var request = URLRequest(url: BackendConfig.functionsURL.appendingPathComponent("search-products"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(await accessToken() ?? BackendConfig.publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue(DeviceID.current, forHTTPHeaderField: "x-device-id")
        request.httpBody = try JSONEncoder().encode(query)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CatalogError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 { throw CatalogError.rateLimited }
        guard status == 200 else { throw CatalogError.badResponse(status) }

        struct Reply: Decodable { var products: [CatalogProduct] }
        return try JSONDecoder().decode(Reply.self, from: data).products
    }
}

// MARK: - Curated list (bundled with the app)

/// A small hand-picked list shipped inside the app, so the Catalog tab is
/// never empty, even offline.
struct CuratedCatalogService: CatalogService {
    let products: [CatalogProduct]

    /// Reads `curated-products.json` from the app bundle.
    init(bundle: Bundle = .main) {
        products = Self.load(from: bundle.url(forResource: "curated-products", withExtension: "json"))
    }

    init(products: [CatalogProduct]) {
        self.products = products
    }

    static func load(from url: URL?) -> [CatalogProduct] {
        guard let url, let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([RawProduct].self, from: data)
        else { return [] }
        return raw.map(ProductNormalizer.normalize)
    }

    func search(_ query: CatalogQuery) async throws -> [CatalogProduct] {
        Array(CatalogRanking.filter(products, query: query, budget: ShoppingBudget()).prefix(query.limit))
    }
}

// MARK: - Live first, list as backup

/// Tries the live catalog; if it fails, answers from the curated list and
/// says so.
struct FallbackCatalogService: Sendable {
    var primary: CatalogService
    var backup: CatalogService

    func search(_ query: CatalogQuery) async -> (products: [CatalogProduct], source: CatalogSource) {
        if let live = try? await primary.search(query) {
            return (live, .live)
        }
        let products = (try? await backup.search(query)) ?? []
        return (products, .curated)
    }
}

/// A random ID for this install, sent with searches so the backend can
/// limit how many one device makes. Not tied to the person or the phone.
enum DeviceID {
    static var current: String {
        let key = "deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}
