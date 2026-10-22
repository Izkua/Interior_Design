import SwiftUI
import UIKit

/// Design tokens: one accent color, warm neutrals, light and dark.
enum Theme {
    // MARK: Colors
    static let accent = Color(light: 0x2F6B5B, dark: 0x7DBBA6)
    /// Text or icons drawn on top of a filled accent surface.
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0E1F19)
    static let background = Color(light: 0xF7F6F2, dark: 0x111110)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1C1C1A)
    static let surfaceAlt = Color(light: 0xEFEDE7, dark: 0x262624)
    static let line = Color(light: 0xE1DED6, dark: 0x343431)
    static let textPrimary = Color(light: 0x1B1B19, dark: 0xF3F2ED)
    static let textSecondary = Color(light: 0x6C6B64, dark: 0x9D9B93)
    static let danger = Color(light: 0xBF3F2B, dark: 0xEE7D69)

    // MARK: Spacing (multiples of 4)
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: Corner radii
    enum Radius {
        static let card: CGFloat = 20
        static let button: CGFloat = 14
        static let small: CGFloat = 10
    }

    /// Apple's minimum comfortable tap target.
    static let minTap: CGFloat = 44
}

/// System font, with a small set of styles that scale with Dynamic Type.
enum Typography {
    static let largeTitle = Font.system(.largeTitle, weight: .bold)
    static let title = Font.system(.title2, weight: .semibold)
    static let headline = Font.system(.headline, weight: .semibold)
    static let body = Font.system(.body)
    static let subheadline = Font.system(.subheadline, weight: .medium)
    static let caption = Font.system(.caption)
}

extension Color {
    /// A color that switches between two hex values in light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
