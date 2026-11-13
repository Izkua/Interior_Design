import Foundation

/// How warm or cool a light's glow is. Bulbs list this as a color
/// temperature in Kelvin: low numbers are yellowy and cozy, high numbers
/// are white-blue like daylight.
enum LightWarmth: String, Codable, CaseIterable, Identifiable, Sendable {
    /// About 2700 to 3000 K: "warm white" or "soft white", like most homes.
    case warm
    /// About 3500 to 4000 K: plain white.
    case neutral
    /// About 5000 K and up: "daylight" or "cool white", like an office.
    case cool

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warm: return "Warm"
        case .neutral: return "Neutral"
        case .cool: return "Cool"
        }
    }

    /// A short description with the usual Kelvin range.
    var detail: String {
        switch self {
        case .warm: return "Yellowy, cozy glow (2700 to 3000 K)"
        case .neutral: return "Plain white (3500 to 4000 K)"
        case .cool: return "Bright daylight white (5000 K and up)"
        }
    }

    /// A typical bulb for this warmth.
    var kelvin: Int {
        switch self {
        case .warm: return 2700
        case .neutral: return 4000
        case .cool: return 5000
        }
    }

    init(kelvin: Int) {
        switch kelvin {
        case ..<3300: self = .warm
        case ..<4600: self = .neutral
        default: self = .cool
        }
    }

    /// How far apart two warmths are: 0 the same, 1 next to each other,
    /// 2 opposite (warm and cool).
    func distance(to other: LightWarmth) -> Int {
        abs(Self.allCases.firstIndex(of: self)! - Self.allCases.firstIndex(of: other)!)
    }

    /// The color family this light flatters: warm light makes warm colors
    /// glow, cool light suits cool colors.
    var tone: RGB.Tone {
        switch self {
        case .warm: return .warm
        case .neutral: return .neutral
        case .cool: return .cool
        }
    }

    /// The light that usually suits a room of this color mood.
    static func suited(to tone: RGB.Tone) -> LightWarmth {
        switch tone {
        case .warm: return .warm
        case .neutral: return .neutral
        case .cool: return .cool
        }
    }

    /// Kinds of item that give off light.
    static func isLight(_ type: ItemType?) -> Bool {
        type == .lamp || type == .tableLamp
    }

    /// Reads the warmth from how a product is described: a Kelvin number
    /// ("2700K") or the words bulbs use ("warm white", "daylight"). Nil
    /// when the text doesn't say.
    static func parse(_ text: String) -> LightWarmth? {
        let lower = text.lowercased()
        // A Kelvin number wins over words: "2700K", "5000 K", "3000-kelvin".
        if let match = lower.firstMatch(of: /(\d{4})\s*-?\s*(k\b|kelvin)/), let k = Int(match.1), (1500...10000).contains(k) {
            return LightWarmth(kelvin: k)
        }
        let words: [(LightWarmth, [String])] = [
            (.cool, ["daylight", "cool white", "cold white", "bright white", "cool light"]),
            (.neutral, ["neutral white", "natural white", "neutral light"]),
            (.warm, ["warm white", "soft white", "warm light", "warm glow", "amber", "edison"]),
        ]
        return words.first { _, keys in keys.contains { lower.contains($0) } }?.0
    }

    /// How well a lamp's light suits the room's light, 0 to 1. Unknown
    /// light scores in the middle, so lamps that don't say aren't buried.
    static func match(_ lamp: LightWarmth?, room: LightWarmth) -> Double {
        guard let lamp else { return 0.5 }
        switch lamp.distance(to: room) {
        case 0: return 1
        case 1: return 0.6
        default: return 0
        }
    }
}

/// The light in a room: what the person said about the main light, and
/// what their lamps give off.
struct RoomLight: Equatable, Sendable {
    /// The ceiling or main light, as the person set it. Nil if not set.
    var mainLight: LightWarmth?
    /// The warmth of each lamp in the room whose light is known.
    var lamps: [LightWarmth] = []

    /// The warmth that new lamps should match: the main light if set,
    /// else what most lamps already give off. Nil when nothing is known.
    var target: LightWarmth? {
        if let mainLight { return mainLight }
        guard !lamps.isEmpty else { return nil }
        let counts = Dictionary(grouping: lamps, by: { $0 }).mapValues(\.count)
        // Ties go to the warmer light, which is what most homes use.
        return LightWarmth.allCases.max { (counts[$0] ?? 0, -$0.kelvin) < (counts[$1] ?? 0, -$1.kelvin) }
    }

    /// True when the room mixes warm and cool light, which tends to look
    /// patchy.
    var isMixed: Bool {
        let all = lamps + [mainLight].compactMap { $0 }
        return all.contains(.warm) && all.contains(.cool)
    }
}
