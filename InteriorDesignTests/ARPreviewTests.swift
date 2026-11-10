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

    // MARK: Standing photo size

    func testStandingPhotoFitsTheTrueSize() {
        // A wide sofa photo: limited by the sofa's width, shorter than its height.
        let wide = PhotoCutout.standingSize(imageWidth: 400, imageHeight: 100, widthCm: 200, depthCm: 90, heightCm: 85)
        XCTAssertEqual(wide.width, 2, accuracy: 0.001)
        XCTAssertEqual(wide.height, 0.5, accuracy: 0.001)
        // A tall lamp photo: as tall as the lamp.
        let tall = PhotoCutout.standingSize(imageWidth: 100, imageHeight: 500, widthCm: 30, depthCm: 30, heightCm: 150)
        XCTAssertEqual(tall.height, 1.5, accuracy: 0.001)
        XCTAssertEqual(tall.width, 0.3, accuracy: 0.001)
    }

    // MARK: Fitting a 3D model

    func testTrueSizeScanKeepsItsSize() {
        let fit = ModelFit.fit(extents: [2, 0.85, 0.9], target: [2, 0.85, 0.9])
        XCTAssertEqual(fit.scale, 1, accuracy: 0.001)
        XCTAssertFalse(fit.turned)
    }

    func testTinyModelFromPhotosIsScaledUpEvenly() {
        // A model built at the wrong scale (1/100) comes up to the saved size.
        let fit = ModelFit.fit(extents: [0.02, 0.0085, 0.009], target: [2, 0.85, 0.9])
        XCTAssertEqual(fit.scale, 100, accuracy: 0.5)
    }

    func testSidewaysModelIsTurnedAndNeverBiggerThanSaved() {
        // Long side along z, but the saved width is the long side.
        let fit = ModelFit.fit(extents: [0.9, 0.85, 2], target: [2, 0.85, 0.9])
        XCTAssertTrue(fit.turned)
        XCTAssertEqual(fit.scale, 1, accuracy: 0.001)
        // Taller than saved: shrinks to the saved height.
        let tall = ModelFit.fit(extents: [2, 1.7, 0.9], target: [2, 0.85, 0.9])
        XCTAssertEqual(tall.scale, 0.5, accuracy: 0.001)
    }

    // MARK: Straightening AI models

    /// Points on the surface of a box (a bench seat on legs is close enough).
    private func boxPoints(_ size: SIMD3<Float>) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        for i in 0...10 { for j in 0...10 { for k in 0...10 where [i, j, k].contains(0) || [i, j, k].contains(10) {
            points.append((SIMD3(Float(i), Float(j), Float(k)) / 10 - 0.5) * size)
        } } }
        return points
    }

    func testStraightensALeaningSlantedBench() {
        let bench = boxPoints([1.2, 0.5, 0.4])
        // As if photographed from above and to the side: tipped 20°, turned 25°.
        let tipped = simd_quatf(angle: 25 * .pi / 180, axis: [0, 1, 0]) * simd_quatf(angle: 20 * .pi / 180, axis: [1, 0, 0])
        let fixed = ModelFit.straightening(bench.map { tipped.act($0) })
        let straight = bench.map { fixed.act(tipped.act($0)) }
        let lo = straight.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
        let hi = straight.reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1) }
        let size = hi - lo
        XCTAssertEqual(size.y, 0.5, accuracy: 0.02, "standing up straight again")
        XCTAssertEqual(max(size.x, size.z), 1.2, accuracy: 0.02, "squared up")
        XCTAssertEqual(min(size.x, size.z), 0.4, accuracy: 0.02, "squared up")
    }

    func testLeavesAStraightTallPieceStanding() {
        let shelf = boxPoints([0.8, 1.8, 0.3])
        let fixed = ModelFit.straightening(shelf)
        let up = fixed.act([0, 1, 0])
        XCTAssertGreaterThan(up.y, 0.99, "never laid down")
    }

    func testStretchFillsTheCatalogSizeExactly() {
        // Long side along x, but the catalog's long side is the depth.
        let fit = ModelFit.stretch(extents: [1.0, 0.4, 0.5], target: [0.43, 0.51, 1.24])
        XCTAssertTrue(fit.turned)
        XCTAssertEqual(fit.scale.x * 1.0, 1.24, accuracy: 0.001)
        XCTAssertEqual(fit.scale.y * 0.4, 0.51, accuracy: 0.001)
        XCTAssertEqual(fit.scale.z * 0.5, 0.43, accuracy: 0.001)
    }
}
