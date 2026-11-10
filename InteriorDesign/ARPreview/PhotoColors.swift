import UIKit

/// A simple color, 0...1 per channel. Kept apart from UIKit types so the
/// color picking can be tested.
struct RGB: Hashable, Sendable {
    var r: Double, g: Double, b: Double

    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }

    /// Straight-line distance between two colors (0 to about 1.7).
    func distance(to other: RGB) -> Double {
        let dr = r - other.r, dg = g - other.g, db = b - other.b
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    func darker(_ amount: Double) -> RGB {
        RGB(r: r * (1 - amount), g: g * (1 - amount), b: b * (1 - amount))
    }

    var brightness: Double { 0.299 * r + 0.587 * g + 0.114 * b }
}

/// The two colors a 3D stand-in is painted with.
struct FurnitureColors: Equatable {
    /// Fabric, top, body.
    var main: RGB
    /// Legs, frame, base.
    var accent: RGB

    static func fallback(for type: ItemType) -> FurnitureColors {
        switch type {
        case .sofa, .chair: return .init(main: RGB(r: 0.62, g: 0.6, b: 0.56), accent: RGB(r: 0.32, g: 0.24, b: 0.18))
        case .bed: return .init(main: RGB(r: 0.92, g: 0.91, b: 0.88), accent: RGB(r: 0.45, g: 0.34, b: 0.25))
        case .rug: return .init(main: RGB(r: 0.78, g: 0.72, b: 0.62), accent: RGB(r: 0.5, g: 0.45, b: 0.4))
        case .lamp: return .init(main: RGB(r: 0.95, g: 0.93, b: 0.88), accent: RGB(r: 0.2, g: 0.2, b: 0.2))
        default: return .init(main: RGB(r: 0.6, g: 0.45, b: 0.32), accent: RGB(r: 0.35, g: 0.26, b: 0.19))
        }
    }
}

/// Picks a piece's main colors from its photo, all on the phone.
///
/// The photo is shrunk to a few hundred pixels, the outer edge (usually
/// wall, floor, or a white product backdrop) is used to learn the
/// background, and the most common remaining colors in the middle win.
enum PhotoColors {
    static func colors(from image: UIImage, type: ItemType) -> FurnitureColors {
        guard let pixels = pixels(of: image, side: 48) else { return .fallback(for: type) }
        return colors(fromPixels: pixels, side: 48) ?? .fallback(for: type)
    }

    /// From a square of pixels, row by row.
    static func colors(fromPixels pixels: [RGB], side: Int) -> FurnitureColors? {
        guard pixels.count == side * side, side >= 8 else { return nil }

        // The background: the most common color around the edge.
        var border: [RGB] = []
        for y in 0..<side {
            for x in 0..<side where x < 2 || y < 2 || x >= side - 2 || y >= side - 2 {
                border.append(pixels[y * side + x])
            }
        }
        let background = groups(border).first?.average

        // The middle of the photo, where the piece usually is.
        let margin = side / 6
        var middle: [RGB] = []
        for y in margin..<(side - margin) {
            for x in margin..<(side - margin) {
                middle.append(pixels[y * side + x])
            }
        }
        var subject = middle.filter { pixel in
            // Product photos are shot on white; skip near-white unless
            // that's all there is (a white sofa).
            guard let background else { return true }
            return pixel.distance(to: background) > 0.12
        }
        // If the piece is the same color as the background, use everything.
        if subject.count < middle.count / 8 { subject = middle }

        let ranked = groups(subject)
        guard let first = ranked.first else { return nil }
        let main = first.average
        // The second color: the next common one that clearly differs, else
        // a darker shade of the main one (for legs and frames).
        let second = ranked.dropFirst().first { $0.count >= subject.count / 12 && $0.average.distance(to: main) > 0.18 }?.average
        return FurnitureColors(main: main, accent: second ?? main.darker(0.4))
    }

    /// Colors from the names catalog products list (like "Grey"), for
    /// products without a photo.
    static func colors(named names: [String], type: ItemType) -> FurnitureColors {
        let table: [String: RGB] = [
            "white": RGB(r: 0.93, g: 0.92, b: 0.9), "black": RGB(r: 0.12, g: 0.12, b: 0.12),
            "grey": RGB(r: 0.55, g: 0.55, b: 0.55), "gray": RGB(r: 0.55, g: 0.55, b: 0.55),
            "beige": RGB(r: 0.85, g: 0.79, b: 0.68), "brown": RGB(r: 0.45, g: 0.31, b: 0.2),
            "green": RGB(r: 0.33, g: 0.48, b: 0.36), "blue": RGB(r: 0.27, g: 0.38, b: 0.58),
        ]
        let found = names.compactMap { table[$0.lowercased()] }
        guard let main = found.first else { return .fallback(for: type) }
        return FurnitureColors(main: main, accent: found.dropFirst().first ?? main.darker(0.4))
    }

    // MARK: Helpers

    struct Group {
        var count = 0
        var sum = RGB(r: 0, g: 0, b: 0)
        var average: RGB { RGB(r: sum.r / Double(count), g: sum.g / Double(count), b: sum.b / Double(count)) }
    }

    /// Sorts pixels into coarse color bins (8 levels per channel) and
    /// returns the bins, most common first.
    static func groups(_ pixels: [RGB]) -> [Group] {
        var bins: [Int: Group] = [:]
        for p in pixels {
            let key = bin(p.r) << 6 | bin(p.g) << 3 | bin(p.b)
            bins[key, default: Group()].count += 1
            bins[key]!.sum.r += p.r
            bins[key]!.sum.g += p.g
            bins[key]!.sum.b += p.b
        }
        return bins.values.sorted { $0.count > $1.count }
    }

    private static func bin(_ value: Double) -> Int { min(7, max(0, Int(value * 8))) }

    /// The photo squeezed to side × side pixels.
    private static func pixels(of image: UIImage, side: Int) -> [RGB]? {
        guard let cg = image.cgImage else { return nil }
        var raw = [UInt8](repeating: 0, count: side * side * 4)
        let drew = raw.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            // See-through product photos (PNG) count as a white backdrop.
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return nil }
        return stride(from: 0, to: raw.count, by: 4).map {
            RGB(r: Double(raw[$0]) / 255, g: Double(raw[$0 + 1]) / 255, b: Double(raw[$0 + 2]) / 255)
        }
    }
}
