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
    /// The room's colors and mood. When set, products that suit it rank higher.
    var vibe: RoomVibe?
    /// The room's light: its main light and the lamps it already has.
    /// When known, lamps with a matching glow rank higher.
    var light: RoomLight?

    /// The glow new lamps should have: the room's light if known, else
    /// the one that suits the room's color mood.
    var lampWarmth: LightWarmth? {
        light?.target ?? vibe.map { LightWarmth.suited(to: $0.tone) }
    }
}

enum CatalogRanking {
    /// Keeps only products that match the query and fit the budget.
    ///
    /// A filter only hides a product when we *know* it doesn't match. The
    /// live catalog often leaves fields blank (no style at all, no rating,
    /// no material), and a blank means "unknown", not "no". The search
    /// words sent to the catalog already ask for the filtered things, so
    /// unknown products stay and simply rank lower.
    static func filter(_ products: [CatalogProduct], query: CatalogQuery, budget: ShoppingBudget) -> [CatalogProduct] {
        products.filter { p in
            // Products of unknown type stay: the search words already asked
            // for this kind of thing.
            if let type = query.type, let pType = p.type, pType != type { return false }
            if let category = query.category, let type = p.type, type.category != category { return false }
            if !query.text.isEmpty {
                let haystack = "\(p.name) \(p.retailer) \(p.materials.joined(separator: " "))".lowercased()
                let words = query.text.lowercased().split(separator: " ")
                if !words.allSatisfy({ haystack.contains($0) }) { return false }
            }
            if let min = query.minPrice, p.price < min { return false }
            if let max = query.maxPrice, p.price > max { return false }
            if let cap = budget.limit(for: p.type), p.price > cap { return false }
            if query.minRating > 0, let rating = p.rating, rating < query.minRating { return false }
            if !query.materials.isEmpty, !p.materials.isEmpty, !matches(p.materials, query.materials) { return false }
            if !query.styles.isEmpty, !p.styles.isEmpty, !matches(p.styles, query.styles) { return false }
            if !query.colors.isEmpty, !p.colors.isEmpty, !matches(p.colors, query.colors) { return false }
            if query.onlyWithSizes, !p.hasDimensions { return false }
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
        case .fits, .fitsSpace: score += 5
        case .unknownSize, .none: score += 1
        case .doesNotFit: score -= 5
        }
        if matches(p.styles, preferences.styles) { score += 2 }
        if matches(p.materials, preferences.materials) { score += 1.5 }
        if matches(p.colors, preferences.colors) { score += 1 }
        if let vibe = preferences.vibe {
            // Colors that suit the room count about as much as a liked style.
            score += 2 * vibe.match(colors: p.colors)
            if matches(p.styles, vibe.suitedStyles) { score += 0.5 }
        }
        if LightWarmth.isLight(p.type), let wanted = preferences.lampWarmth {
            // A lamp whose glow matches the room counts about as much as a
            // liked style; warm in a cool room (or the reverse) counts against.
            score += 3 * LightWarmth.match(p.lightWarmth, room: wanted) - 1.5
        }
        if let light = preferences.light?.target, light != .neutral, !p.colors.isEmpty {
            // Warm light makes warm colors glow and dulls cool ones; cool
            // light the other way round. A small nudge.
            if p.colors.contains(where: { RoomVibe.tone(ofName: $0.capitalized) == light.tone }) { score += 0.3 }
        }
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

    /// True when a product value matches one of the wanted options,
    /// ignoring case. Catalog data is worded freely ("Solid Oak", "Light
    /// Gray", "Polyester blend"), so a value matches when it contains the
    /// option or one of its related words.
    static func matches(_ values: [String], _ wanted: Set<String>) -> Bool {
        guard !wanted.isEmpty else { return false }
        let words = Set(wanted.flatMap { option -> [String] in
            let key = option.lowercased()
            return [key] + (relatedWords[key] ?? [])
        })
        return values.contains { value in
            let v = value.lowercased()
            // Single words match the start of a word, so "upholstered"
            // counts as fabric but "cashmere" doesn't count as ash wood.
            let valueWords = v.split { !$0.isLetter }
            return words.contains { word in
                word.contains(where: { !$0.isLetter })
                    ? v.contains(word)
                    : valueWords.contains { $0.hasPrefix(word) }
            }
        }
    }

    /// Everyday words retailers use for each filter option.
    static let relatedWords: [String: [String]] = [
        // Materials
        "wood": ["oak", "walnut", "pine", "acacia", "mango", "teak", "birch", "ash", "beech", "maple",
                 "cherry", "bamboo", "plywood", "mdf", "veneer", "timber"],
        "metal": ["steel", "iron", "aluminum", "aluminium", "brass", "chrome", "copper", "bronze"],
        "fabric": ["polyester", "linen", "cotton", "velvet", "boucle", "bouclé", "chenille", "wool",
                   "upholster", "textile", "microfiber", "tweed", "nylon"],
        "leather": ["leatherette", "suede"],
        "glass": ["mirror", "tempered"],
        "rattan": ["wicker", "cane", "seagrass", "jute"],
        // Colors
        "grey": ["gray", "charcoal", "slate", "silver"],
        "white": ["ivory", "cream", "off-white", "alabaster"],
        "beige": ["cream", "tan", "taupe", "sand", "natural", "oatmeal", "khaki", "linen"],
        "brown": ["walnut", "espresso", "chocolate", "coffee", "chestnut", "mahogany", "cognac", "caramel"],
        "black": ["ebony", "onyx", "jet"],
        "green": ["olive", "sage", "emerald", "forest"],
        "blue": ["navy", "teal", "indigo", "cobalt", "denim"],
        // Styles
        "modern": ["contemporary", "mid-century", "mid century"],
        "scandinavian": ["scandi", "nordic"],
        "minimal": ["minimalist"],
        "classic": ["traditional", "vintage"],
        "warm": ["rustic", "farmhouse", "boho"],
    ]
}
