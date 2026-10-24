import Foundation

/// Budget for shopping one room: a total, and optionally a cap per kind
/// of item ("sofa: $800").
struct ShoppingBudget: Sendable, Equatable {
    var total: Double?
    var perItem: [ItemType: Double] = [:]
    /// Already spent or planned (for example, items on the wishlist).
    var committed: Double = 0

    var remaining: Double? {
        total.map { max($0 - committed, 0) }
    }

    /// The most a product of this type may cost: its own cap, the money
    /// left, whichever is lower.
    func limit(for type: ItemType?) -> Double? {
        let caps = [type.flatMap { perItem[$0] }, remaining].compactMap { $0 }
        return caps.min()
    }
}

/// What the person likes, used to rank results.
struct ShoppingPreferences: Sendable, Equatable {
    var styles: Set<String> = []
    var materials: Set<String> = []
    var colors: Set<String> = []
    var minRating: Double = 0
}

enum CatalogRanking {
    /// Keeps only products that match the query and fit the budget.
    static func filter(_ products: [CatalogProduct], query: CatalogQuery, budget: ShoppingBudget) -> [CatalogProduct] {
        products.filter { p in
            if let type = query.type, p.type != type { return false }
            if !query.text.isEmpty {
                let haystack = "\(p.name) \(p.retailer) \(p.materials.joined(separator: " "))".lowercased()
                let words = query.text.lowercased().split(separator: " ")
                if !words.allSatisfy({ haystack.contains($0) }) { return false }
            }
            if let min = query.minPrice, p.price < min { return false }
            if let max = query.maxPrice, p.price > max { return false }
            if let cap = budget.limit(for: p.type), p.price > cap { return false }
            // A minimum rating hides products with no rating at all.
            if query.minRating > 0, (p.rating ?? 0) < query.minRating { return false }
            if !query.materials.isEmpty, !matches(p.materials, query.materials) { return false }
            if !query.styles.isEmpty, !matches(p.styles, query.styles) { return false }
            if !query.colors.isEmpty, !matches(p.colors, query.colors) { return false }
            return true
        }
    }

    /// Best first: fits the room, matches what the person likes, well
    /// rated, and comfortably within budget.
    static func rank(
        _ products: [CatalogProduct],
        preferences: ShoppingPreferences,
        budget: ShoppingBudget,
        fit: [String: FitResult] = [:]
    ) -> [CatalogProduct] {
        products
            .map { ($0, score($0, preferences: preferences, budget: budget, fit: fit[$0.id])) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.price < $1.0.price }
            .map(\.0)
    }

    static func score(_ p: CatalogProduct, preferences: ShoppingPreferences, budget: ShoppingBudget, fit: FitResult?) -> Double {
        var score = 0.0
        switch fit {
        case .fits: score += 5
        case .unknownSize, .none: score += 1
        case .doesNotFit: score -= 5
        }
        if matches(p.styles, preferences.styles) { score += 2 }
        if matches(p.materials, preferences.materials) { score += 1.5 }
        if matches(p.colors, preferences.colors) { score += 1 }
        if let rating = p.rating {
            // A 4.5 with 500 reviews beats a 5.0 with 2.
            let confidence = min(Double(p.reviewCount ?? 0) / 50, 1)
            score += (rating - 3) * (0.5 + 0.5 * confidence)
        }
        if let cap = budget.limit(for: p.type), cap > 0 {
            // A little credit for leaving money to spare.
            score += max(0, 1 - p.price / cap)
        }
        return score
    }

    /// True when the two lists share a word, ignoring case.
    private static func matches(_ values: [String], _ wanted: Set<String>) -> Bool {
        guard !wanted.isEmpty else { return false }
        let lower = Set(wanted.map { $0.lowercased() })
        return values.contains { lower.contains($0.lowercased()) }
    }
}
