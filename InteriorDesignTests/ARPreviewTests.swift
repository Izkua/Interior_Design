import XCTest
import simd
@testable import InteriorDesign

final class ARPreviewTests: XCTestCase {
    // MARK: Shapes stay true to size

    func testEveryTypeFillsExactlyItsSavedSize() {
        let sizes: [(Double, Double, Double)] = [(200, 90, 85), (50, 50, 90), (140, 70, 75), (30, 30, 150), (80, 30, 180), (160, 200, 50), (45, 40, 40)]
        for type in ItemType.allCases {
            for (w, d, h) in sizes {
                let parts = FurnitureShape.parts(type: type, widthCm: w, depthCm: d, heightCm: h)
                XCTAssertFalse(parts.isEmpty, "\(type)")
                let (lo, hi) = FurnitureShape.bounds(of: parts)
                let tolerance: Float = 0.002
                // Never bigger than the saved size.
                XCTAssertGreaterThanOrEqual(lo.x, Float(-w / 200) - tolerance, "\(type) \(w)")
                XCTAssertLessThanOrEqual(hi.x, Float(w / 200) + tolerance, "\(type) \(w)")
                XCTAssertGreaterThanOrEqual(lo.z, Float(-d / 200) - tolerance, "\(type) \(d)")
                XCTAssertLessThanOrEqual(hi.z, Float(d / 200) + tolerance, "\(type) \(d)")
                XCTAssertGreaterThanOrEqual(lo.y, -tolerance, "\(type) stands on the floor")
                XCTAssertLessThanOrEqual(hi.y, Float(h / 100) + tolerance, "\(type) \(h)")
                // And the full width and depth are used.
                XCTAssertEqual(hi.x - lo.x, Float(w / 100), accuracy: 0.02, "\(type) width")
                XCTAssertEqual(hi.z - lo.z, Float(d / 100), accuracy: 0.02, "\(type) depth")
                if type != .rug {
                    XCTAssertEqual(hi.y, Float(h / 100), accuracy: 0.01, "\(type) height")
                }
                for part in parts {
                    XCTAssertTrue(part.size.min() > 0, "\(type) part has a size")
                    XCTAssertLessThanOrEqual(part.cornerRadius, part.size.min() / 2, "\(type) corner")
                }
            }
        }
    }

    func testSofaHasBackAndArmsAndTableHasLegs() {
        let sofa = FurnitureShape.parts(type: .sofa, widthCm: 200, depthCm: 90, heightCm: 85)
        XCTAssertGreaterThanOrEqual(sofa.filter { $0.tone == .main }.count, 4, "seat, back, two arms")
        let table = FurnitureShape.parts(type: .table, widthCm: 140, depthCm: 80, heightCm: 75)
        XCTAssertEqual(table.filter { $0.tone == .accent }.count, 4, "four legs")
    }

    func testTinySizesDontBreak() {
        for type in ItemType.allCases {
            let parts = FurnitureShape.parts(type: type, widthCm: 2, depthCm: 2, heightCm: 1)
            XCTAssertTrue(parts.allSatisfy { $0.size.min() > 0 && $0.center.x.isFinite })
        }
    }

    // MARK: Colors from a photo

    private func image(side: Int, background: RGB, subject: RGB, inset: Int) -> [RGB] {
        (0..<side * side).map { i in
            let x = i % side, y = i / side
            let inside = x >= inset && x < side - inset && y >= inset && y < side - inset
            return inside ? subject : background
        }
    }

    func testPicksTheSubjectNotTheWhiteBackdrop() {
        let blue = RGB(r: 0.2, g: 0.3, b: 0.7)
        let pixels = image(side: 48, background: RGB(r: 1, g: 1, b: 1), subject: blue, inset: 12)
        let colors = PhotoColors.colors(fromPixels: pixels, side: 48)
        XCTAssertNotNil(colors)
        XCTAssertLessThan(colors!.main.distance(to: blue), 0.05)
        XCTAssertLessThan(colors!.accent.brightness, colors!.main.brightness, "accent falls back to a darker shade")
    }

    func testWhiteSofaOnWhiteStillComesOutWhite() {
        let white = RGB(r: 0.97, g: 0.97, b: 0.97)
        let pixels = image(side: 48, background: white, subject: white, inset: 12)
        let colors = PhotoColors.colors(fromPixels: pixels, side: 48)
        XCTAssertLessThan(colors!.main.distance(to: white), 0.05)
    }

    func testSecondColorWhenClearlyDifferent() {
        let green = RGB(r: 0.3, g: 0.5, b: 0.3), wood = RGB(r: 0.45, g: 0.3, b: 0.15)
        var pixels = image(side: 48, background: RGB(r: 1, g: 1, b: 1), subject: green, inset: 10)
        // Legs: a band of wood across the lower middle.
        for y in 30..<36 { for x in 10..<38 { pixels[y * 48 + x] = wood } }
        let colors = PhotoColors.colors(fromPixels: pixels, side: 48)!
        XCTAssertLessThan(colors.main.distance(to: green), 0.05)
        XCTAssertLessThan(colors.accent.distance(to: wood), 0.05)
    }

    func testColorNamesForProductsWithoutPhoto() {
        let colors = PhotoColors.colors(named: ["Grey", "Black"], type: .sofa)
        XCTAssertEqual(colors.main, RGB(r: 0.55, g: 0.55, b: 0.55))
        XCTAssertEqual(colors.accent, RGB(r: 0.12, g: 0.12, b: 0.12))
        XCTAssertEqual(PhotoColors.colors(named: [], type: .bed), .fallback(for: .bed))
    }

    func testProductWithoutSizeCantBePlaced() {
        var product = CatalogProduct.placeholder
        XCTAssertNotNil(ARPiece(product: product))
        product.depthCm = nil
        XCTAssertNil(ARPiece(product: product))
    }
}
