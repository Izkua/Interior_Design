import Foundation

/// Color words for an RGB color, all worked out on the phone (free and
/// offline).
extension RGB {
    /// 0 for grey, up to 1 for a pure color.
    var saturation: Double {
        let high = max(r, g, b), low = min(r, g, b)
        return high == 0 ? 0 : (high - low) / high
    }

    /// Hue in degrees, 0 to 360 (red is 0).
    var hue: Double {
        let high = max(r, g, b), low = min(r, g, b)
        let delta = high - low
        guard delta > 0.0001 else { return 0 }
        var h: Double
        if high == r { h = (g - b) / delta }
        else if high == g { h = (b - r) / delta + 2 }
        else { h = (r - g) / delta + 4 }
        h *= 60
        return h < 0 ? h + 360 : h
    }

    enum Tone: String, Sendable { case warm, cool, neutral }

    /// Reds, oranges, yellows, and browns are warm; greens, blues, and
    /// purples are cool; greys, whites, and blacks are neutral. Beige and
    /// tan, being faintly warm, count as warm.
    var tone: Tone {
        guard saturation > 0.12, brightness > 0.08 else { return .neutral }
        let h = hue
        return (h < 70 || h >= 330) ? .warm : .cool
    }

    /// The nearest of the color names the catalog uses (see `ColorOption`).
    var colorName: String {
        if brightness > 0.86, saturation < 0.12 { return "White" }
        if brightness < 0.18 { return "Black" }
        if saturation < 0.14 { return "Grey" }
        let h = hue
        switch h {
        case 0..<50, 330...360:
            // Light, soft warm colors read as beige; deeper ones as brown.
            return brightness > 0.62 && saturation < 0.45 ? "Beige" : "Brown"
        case 50..<75: return brightness > 0.6 ? "Beige" : "Brown"
        case 75..<170: return "Green"
        default: return "Blue"
        }
    }

    /// "#A0703C", for saving.
    var hex: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6, let value = Int(clean, radix: 16) else { return nil }
        self.init(r: Double((value >> 16) & 0xFF) / 255, g: Double((value >> 8) & 0xFF) / 255, b: Double(value & 0xFF) / 255)
    }
}

/// The general color and mood of a room, from the colors of what's in it.
struct RoomVibe: Equatable, Sendable {
    /// The room's main colors as catalog color names, most common first.
    var colorNames: [String]
    /// A few colors to show as swatches.
    var swatches: [RGB]
    var tone: RGB.Tone
    /// 0 is very dark, 1 very light.
    var lightness: Double
    /// 0 is all greys, 1 very colorful.
    var colorfulness: Double

    static let neutralNames: Set<String> = ["White", "Black", "Grey", "Beige"]

    /// A short name for the mood, like "Warm and earthy".
    var title: String {
        if colorfulness > 0.5 { return "Bold and colorful" }
        let light = lightness > 0.62 ? 2 : lightness < 0.35 ? 0 : 1
        switch (tone, light) {
        case (.neutral, 2): return "Bright and airy"
        case (.neutral, 1): return "Soft neutrals"
        case (.neutral, _): return "Dark and moody"
        case (.warm, 2): return "Warm and light"
        case (.warm, 1): return "Warm and earthy"
        case (.warm, _): return "Rich and cozy"
        case (.cool, 2): return "Cool and fresh"
        case (.cool, 1): return "Calm and cool"
        case (.cool, _): return "Deep and cool"
        }
    }

    /// Catalog styles that usually suit this mood, used as a light nudge
    /// when ranking.
    var suitedStyles: Set<String> {
        switch tone {
        case .warm: return lightness > 0.55 ? ["Scandinavian", "Warm"] : ["Warm", "Classic"]
        case .cool: return ["Modern", "Minimal"]
        case .neutral: return lightness < 0.35 ? ["Industrial", "Modern"] : ["Minimal", "Scandinavian"]
        }
    }

    /// The vibe of a set of colors, each weighted (by size, so a big sofa
    /// counts more than a candle). Nil when there are no colors.
    static func from(_ colors: [(color: RGB, weight: Double)]) -> RoomVibe? {
        let usable = colors.filter { $0.weight > 0 }
        let total = usable.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }

        var nameWeights: [String: Double] = [:]
        var toneWeights: [RGB.Tone: Double] = [:]
        var lightness = 0.0
        var colorfulness = 0.0
        for (color, weight) in usable {
            nameWeights[color.colorName, default: 0] += weight
            toneWeights[color.tone, default: 0] += weight
            lightness += color.brightness * weight
            colorfulness += color.saturation * weight
        }
        let names = nameWeights.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        // Warm or cool only when that clearly leads; otherwise neutral.
        let warm = toneWeights[.warm] ?? 0, cool = toneWeights[.cool] ?? 0
        let tone: RGB.Tone = warm > cool * 1.3 && warm > total * 0.3 ? .warm
            : cool > warm * 1.3 && cool > total * 0.3 ? .cool : .neutral
        let swatches = usable.sorted { $0.weight > $1.weight }.map(\.color)
        return RoomVibe(
            colorNames: Array(names.prefix(4)),
            swatches: Array(distinct(swatches).prefix(5)),
            tone: tone,
            lightness: lightness / total,
            colorfulness: colorfulness / total
        )
    }

    /// How well a product's listed colors suit the room, 0 to 1.
    /// A color already in the room scores best; neutrals go with anything;
    /// a color of the same warmth is fine; anything else scores 0.
    func match(colors: [String]) -> Double {
        guard !colors.isEmpty else { return 0 }
        let room = Set(colorNames)
        return colors.map { name -> Double in
            let n = name.capitalized == "Gray" ? "Grey" : name.capitalized
            if room.contains(n) { return 1 }
            if Self.neutralNames.contains(n) { return 0.6 }
            if Self.tone(ofName: n) == tone { return 0.5 }
            return 0
        }.max() ?? 0
    }

    static func tone(ofName name: String) -> RGB.Tone {
        switch name {
        case "Brown", "Beige": return .warm
        case "Green", "Blue": return .cool
        default: return .neutral
        }
    }

    /// Drops colors that look almost the same as one already kept.
    private static func distinct(_ colors: [RGB]) -> [RGB] {
        var kept: [RGB] = []
        for c in colors where !kept.contains(where: { $0.distance(to: c) < 0.15 }) { kept.append(c) }
        return kept
    }
}
