import XCTest
@testable import InteriorDesign

final class CutoutMaskTests: XCTestCase {
    private func photo() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
    }

    func testNothingKeptUntilPainted() throws {
        let mask = try XCTUnwrap(CutoutMask(photo: photo(), findObjects: false))
        XCTAssertNil(mask.cutout([]), "nothing chosen or painted")
    }

    func testPaintingAddsAreaAndErasingRemovesIt() throws {
        let mask = try XCTUnwrap(CutoutMask(photo: photo(), findObjects: false))
        // A stroke across the middle, left to right.
        mask.stroke(from: CGPoint(x: 0.25, y: 0.5), to: CGPoint(x: 0.75, y: 0.5), brush: 0.05, erasing: false)
        let painted = try XCTUnwrap(mask.cutout([]))
        XCTAssertEqual(Double(painted.width), 220, accuracy: 20, "about half the width plus the brush")
        XCTAssertLessThan(painted.height, 60, "a thin stroke, cropped tight")

        // Erase the right half of it.
        mask.stroke(from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.8, y: 0.5), brush: 0.1, erasing: true)
        let erased = try XCTUnwrap(mask.cutout([]))
        XCTAssertLessThan(erased.width, painted.width - 60)

        mask.resetStrokes()
        XCTAssertNil(mask.cutout([]))
    }
}

final class ModelInputTests: XCTestCase {
    func testCutoutIsCenteredOnASquareWithRoomAround() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let tall = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 600), format: format).image { c in
            UIColor.brown.setFill(); c.fill(CGRect(x: 0, y: 0, width: 300, height: 600))
        }
        let png = try XCTUnwrap(PhotoCutout.modelInput(try XCTUnwrap(tall.cgImage)))
        let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
        XCTAssertEqual(image.width, image.height, "square")
        XCTAssertEqual(Double(image.height), 600 / 0.85, accuracy: 2, "the piece fills about 85%")
    }
}
