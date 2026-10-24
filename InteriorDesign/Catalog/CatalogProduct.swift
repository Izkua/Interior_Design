import Foundation

/// A product from the catalog, as the app uses it. Search results are
/// these plain values; only wishlist items are saved to the database (as
/// `Product`). All sizes are centimeters.
struct CatalogProduct: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var price: Double
    var currency: String = "USD"
    /// Nil when the retailer does not list a size. Such products are shown,
    /// but never marked as fitting.
    var widthCm: Double?
    var depthCm: Double?
    var heightCm: Double?
    /// What kind of furniture it is, if known.
    var type: ItemType?
    var materials: [String] = []
    var styles: [String] = []
    var colors: [String] = []
    var rating: Double?
    var reviewCount: Int?
    var imageURL: URL?
    var retailer: String
    /// The retailer page. Nil for sample products.
    var url: URL?
    /// True for placeholder products used before real catalog data exists.
    var isSample: Bool = false

    /// A stand-in shape for loading placeholders.
    static let placeholder = CatalogProduct(
        id: "placeholder", name: "Loading product name", price: 100,
        widthCm: 100, depthCm: 50, heightCm: 80, retailer: "Store"
    )

    var hasDimensions: Bool {
        (widthCm ?? 0) > 0 && (depthCm ?? 0) > 0 && (heightCm ?? 0) > 0
    }

    /// The product as a piece of furniture for the layout engine, or nil
    /// if its size is unknown.
    func asLayoutItem(id itemID: UUID = UUID()) -> LayoutItem? {
        guard hasDimensions, let w = widthCm, let d = depthCm, let h = heightCm else { return nil }
        return LayoutItem(id: itemID, type: type ?? .other, name: name, width: w, depth: d, height: h)
    }
}

/// What to search for. Every filter is optional.
struct CatalogQuery: Codable, Hashable, Sendable {
    var text = ""
    var type: ItemType?
    var minPrice: Double?
    var maxPrice: Double?
    var minRating: Double = 0
    var materials: Set<String> = []
    var styles: Set<String> = []
    var colors: Set<String> = []
    var limit = 30
}

/// Colors a person can filter by.
enum ColorOption {
    static let all = ["White", "Black", "Grey", "Beige", "Brown", "Green", "Blue"]
}

// MARK: - Turning outside data into CatalogProduct

/// A product as written in the curated list (or returned by another
/// source), before sizes are converted to centimeters.
struct RawProduct: Codable, Sendable {
    struct Size: Codable, Sendable {
        var width: Double?
        var depth: Double?
        var height: Double?
        /// "cm", "in", "mm", or "m". Missing means cm.
        var unit: String?
    }

    var id: String
    var name: String
    var price: Double
    var currency: String?
    var size: Size?
    var type: String?
    var materials: [String]?
    var styles: [String]?
    var colors: [String]?
    var rating: Double?
    var reviewCount: Int?
    var imageURL: String?
    var retailer: String
    var url: String?
    var isSample: Bool?
}

enum ProductNormalizer {
    /// Converts sizes to centimeters, matches the type to our list, and
    /// drops anything that cannot be a real size (zero, negative, or over
    /// 10 meters, which is usually a units mistake in the source).
    static func normalize(_ raw: RawProduct) -> CatalogProduct {
        let factor = centimeters(per: raw.size?.unit)
        func clean(_ value: Double?) -> Double? {
            guard let value, value > 0 else { return nil }
            let cm = value * factor
            return cm <= 1_000 ? cm : nil
        }
        return CatalogProduct(
            id: raw.id,
            name: raw.name.trimmingCharacters(in: .whitespacesAndNewlines),
            price: max(raw.price, 0),
            currency: raw.currency ?? "USD",
            widthCm: clean(raw.size?.width),
            depthCm: clean(raw.size?.depth),
            heightCm: clean(raw.size?.height),
            type: itemType(raw.type, name: raw.name),
            materials: raw.materials ?? [],
            styles: raw.styles ?? [],
            colors: raw.colors ?? [],
            rating: raw.rating.map { min(max($0, 0), 5) },
            reviewCount: raw.reviewCount,
            imageURL: raw.imageURL.flatMap(URL.init(string:)),
            retailer: raw.retailer,
            url: raw.url.flatMap(URL.init(string:)),
            isSample: raw.isSample ?? false
        )
    }

    static func centimeters(per unit: String?) -> Double {
        switch unit?.lowercased() {
        case "in", "inch", "inches": return Length.cmPerInch
        case "mm": return 0.1
        case "m": return 100
        case "ft", "feet": return Length.cmPerFoot
        default: return 1
        }
    }

    /// Our item type from a category name, or from words in the product
    /// name if the category is missing.
    static func itemType(_ category: String?, name: String) -> ItemType? {
        let text = "\(category ?? "") \(name)".lowercased()
        let words: [(ItemType, [String])] = [
            (.tvStand, ["tv stand", "media console", "tv console", "entertainment center"]),
            (.sofa, ["sofa", "couch", "sectional", "loveseat"]),
            (.bed, ["bed frame", "platform bed", " bed"]),
            (.desk, ["desk"]),
            (.dresser, ["dresser", "chest of drawers"]),
            (.shelf, ["bookcase", "bookshelf", "shelf", "shelving"]),
            (.lamp, ["lamp"]),
            (.rug, ["rug"]),
            (.chair, ["armchair", "chair", "accent chair"]),
            (.table, ["coffee table", "dining table", "side table", "table"]),
        ]
        if let raw = category?.lowercased(), let exact = ItemType(rawValue: raw) { return exact }
        return words.first { _, keys in keys.contains { text.contains($0) } }?.0
    }
}
