import Foundation

/// Every length in the app is stored in centimeters. These helpers
/// convert to and from what the person sees and types.
enum UnitSystem: String, CaseIterable, Identifiable {
    case imperial
    case metric

    var id: String { rawValue }

    /// Short label for a segmented picker.
    var title: String {
        switch self {
        case .imperial: return "ft / in"
        case .metric: return "m / cm"
        }
    }

    /// Example shown as the placeholder in a length field.
    var example: String {
        switch self {
        case .imperial: return "12′ 6″"
        case .metric: return "3.8 m"
        }
    }

    /// Imperial in the US, metric elsewhere.
    static var deviceDefault: UnitSystem {
        Locale.current.measurementSystem == .us ? .imperial : .metric
    }
}

/// What a length measures, which changes what a bare number means.
/// "12" is 12 feet for a wall but 12 inches for a stool.
enum LengthScale {
    /// Walls and rooms: bare numbers are feet, or meters (centimeters when
    /// the number is too big to be meters).
    case room
    /// Furniture: bare numbers are inches, or centimeters.
    case furniture

    func example(_ system: UnitSystem) -> String {
        switch self {
        case .room: return system.example
        case .furniture: return system == .imperial ? "34″" : "85 cm"
        }
    }
}

enum Length {
    static let cmPerInch = 2.54
    static let cmPerFoot = 30.48

    // MARK: Formatting

    /// Room-scale length: "12′ 6″" or "3.8 m".
    static func format(_ cm: Double, system: UnitSystem) -> String {
        switch system {
        case .metric:
            if cm >= 100 {
                return "\(trimmed(cm / 100, decimals: 2)) m"
            }
            return "\(Int(cm.rounded())) cm"
        case .imperial:
            let totalInches = Int((cm / cmPerInch).rounded())
            let feet = totalInches / 12
            let inches = totalInches % 12
            if feet == 0 { return "\(inches)″" }
            if inches == 0 { return "\(feet)′" }
            return "\(feet)′ \(inches)″"
        }
    }

    /// One furniture measurement: "34″" or "85 cm". Small sizes, like a
    /// rug's thickness, keep one decimal so they never show as zero.
    static func formatFurniture(_ cm: Double, system: UnitSystem) -> String {
        switch system {
        case .metric:
            return cm < 10 ? "\(trimmed(cm, decimals: 1)) cm" : "\(Int(cm.rounded())) cm"
        case .imperial:
            let inches = cm / cmPerInch
            return inches < 10 ? "\(trimmed(inches, decimals: 1))″" : "\(Int(inches.rounded()))″"
        }
    }

    /// Either kind of length, formatted for its scale.
    static func format(_ cm: Double, system: UnitSystem, scale: LengthScale) -> String {
        scale == .room ? format(cm, system: system) : formatFurniture(cm, system: system)
    }

    /// Furniture size: "210 × 90 × 85 cm" or "83 × 35 × 33 in".
    static func formatDimensions(width: Double, depth: Double, height: Double, system: UnitSystem) -> String {
        switch system {
        case .metric:
            return "\(Int(width.rounded())) × \(Int(depth.rounded())) × \(Int(height.rounded())) cm"
        case .imperial:
            func inches(_ cm: Double) -> Int { Int((cm / cmPerInch).rounded()) }
            return "\(inches(width)) × \(inches(depth)) × \(inches(height)) in"
        }
    }

    /// Floor area: "12.5 m²" or "135 sq ft".
    static func formatArea(_ squareCm: Double, system: UnitSystem) -> String {
        switch system {
        case .metric:
            return "\(trimmed(squareCm / 10_000, decimals: 1)) m²"
        case .imperial:
            return "\(Int((squareCm / (cmPerFoot * cmPerFoot)).rounded())) sq ft"
        }
    }

    // MARK: Parsing

    /// Reads what a person types and returns centimeters, or nil if it
    /// cannot be understood.
    ///
    /// Accepts, for example: `12'6"`, `12′ 6″`, `12 ft 6 in`, `12.5`
    /// (feet when imperial), `3.8` (meters when metric), `380` (centimeters
    /// when metric, because the number is too big to be meters), `3.8 m`,
    /// `380 cm`.
    ///
    /// With `scale: .furniture`, a bare number is inches (imperial) or
    /// centimeters (metric) instead: `34` is a 34-inch table, and `6' 2"`
    /// still works.
    static func parse(_ raw: String, system: UnitSystem, scale: LengthScale = .room) -> Double? {
        var text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // The iOS keyboard may type curly quotes; treat them as ' and ".
        let replacements: [(String, String)] = [
            ("′", "'"), ("’", "'"), ("‘", "'"),
            ("″", "\""), ("”", "\""), ("“", "\""),
            (",", ".")
        ]
        for (from, to) in replacements {
            text = text.replacingOccurrences(of: from, with: to)
        }

        guard !text.isEmpty, let parsed = pairs(in: text), !parsed.isEmpty else {
            return nil
        }

        var total = 0.0
        var previousWasFeet = false
        for pair in parsed {
            var unit = pair.unit
            if unit.isEmpty {
                switch (scale, system) {
                case (.furniture, .metric):
                    unit = "cm"
                case (.furniture, .imperial):
                    unit = "in"
                case (.room, .metric):
                    // People type "3.8" for meters but "380" for
                    // centimeters; no room wall is over 30 m.
                    unit = pair.value > 30 ? "cm" : "m"
                case (.room, .imperial):
                    // "12' 6" means 12 feet 6 inches; a lone "12" means feet.
                    unit = previousWasFeet ? "in" : "ft"
                }
            }
            guard let factor = centimeters(perUnit: unit) else { return nil }
            total += pair.value * factor
            previousWasFeet = (factor == cmPerFoot)
        }
        return total > 0 ? total : nil
    }

    // MARK: Private helpers

    /// Splits "12ft 6in" into [(12, "ft"), (6, "in")].
    private static func pairs(in text: String) -> [(value: Double, unit: String)]? {
        var result: [(value: Double, unit: String)] = []
        var number = ""
        var unit = ""

        for ch in text {
            if ch.isNumber || ch == "." {
                if !unit.isEmpty {
                    // A new number starts, so the previous pair is complete.
                    guard let value = Double(number) else { return nil }
                    result.append((value: value, unit: unit))
                    number = ""
                    unit = ""
                }
                number.append(ch)
            } else if ch == " " {
                if !unit.isEmpty {
                    guard let value = Double(number) else { return nil }
                    result.append((value: value, unit: unit))
                    number = ""
                    unit = ""
                }
            } else {
                unit.append(ch)
            }
        }

        if !number.isEmpty {
            guard let value = Double(number) else { return nil }
            result.append((value: value, unit: unit))
        } else if !unit.isEmpty {
            return nil
        }
        return result
    }

    private static func centimeters(perUnit unit: String) -> Double? {
        switch unit {
        case "'", "ft", "feet", "foot":
            return cmPerFoot
        case "\"", "in", "inch", "inches", "''":
            return cmPerInch
        case "m", "meter", "meters", "metre", "metres":
            return 100
        case "cm":
            return 1
        case "mm":
            return 0.1
        default:
            return nil
        }
    }

    private static func trimmed(_ value: Double, decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }
}
