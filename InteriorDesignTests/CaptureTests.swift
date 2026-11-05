import simd
import XCTest
@testable import InteriorDesign

final class CaptureTests: XCTestCase {
    // MARK: Vision labels → item types

    func testMapsCommonLabels() {
        XCTAssertEqual(LabelMapper.label(from: [("couch", 0.8)])?.type, .sofa)
        XCTAssertEqual(LabelMapper.label(from: [("coffee_table", 0.6)])?.type, .table)
        XCTAssertEqual(LabelMapper.label(from: [("bookshelf", 0.5)])?.type, .shelf)
        XCTAssertEqual(LabelMapper.label(from: [("floor_lamp", 0.7)])?.type, .lamp)
        XCTAssertEqual(LabelMapper.label(from: [("chest_of_drawers", 0.4)])?.type, .dresser)
    }

    func testMatchesWholeWordsOnly() {
        // "vegetable" contains "table", but is not one.
        XCTAssertNil(LabelMapper.label(from: [("vegetable", 0.9)]))
        XCTAssertNil(LabelMapper.label(from: [("cat", 0.9), ("banana", 0.5)]))
    }

    func testCombinesEvidenceAndIgnoresNoise() throws {
        // Two medium labels for chairs beat one stronger label for a table.
        let label = try XCTUnwrap(LabelMapper.label(from: [("table", 0.6), ("chair", 0.5), ("armchair", 0.4), ("rug", 0.01)]))
        XCTAssertEqual(label.type, .chair)
        XCTAssertEqual(label.confidence, 0.7, accuracy: 0.001)   // 1 − 0.5 × 0.6
        XCTAssertLessThanOrEqual(label.confidence, 1)
    }

    func testConfidenceNotes() {
        XCTAssertTrue(ItemLabel(type: .sofa, confidence: 0.8, rawLabel: "couch").confidenceNote.contains("fairly sure"))
        XCTAssertTrue(ItemLabel(type: .sofa, confidence: 0.4, rawLabel: "couch").confidenceNote.contains("check"))
        XCTAssertTrue(ItemLabel(type: .sofa, confidence: 0.1, rawLabel: "couch").confidenceNote.contains("not sure"))
    }

    // MARK: Reference-object scale

    func testWalletCardScale() throws {
        // A card spanning 100 points means 0.0856 cm per point.
        let scale = try XCTUnwrap(ReferenceScale(
            referenceStart: CGPoint(x: 0, y: 0), referenceEnd: CGPoint(x: 100, y: 0),
            knownLengthCm: ReferenceObject.walletCard.lengthCm!
        ))
        // A sofa 2,000 points wide is 171.2 cm.
        XCTAssertEqual(scale.length(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 2000, y: 50)) ?? 0, 171.2, accuracy: 0.001)
        // Diagonal taps use the straight-line distance (3-4-5).
        XCTAssertEqual(scale.length(from: .zero, to: CGPoint(x: 300, y: 400)) ?? 0, 42.8, accuracy: 0.001)
    }

    func testDoorScale() throws {
        let scale = try XCTUnwrap(ReferenceScale(
            referenceStart: CGPoint(x: 10, y: 0), referenceEnd: CGPoint(x: 10, y: 1000),
            knownLengthCm: ReferenceObject.doorHeight.lengthCm!
        ))
        XCTAssertEqual(scale.length(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 420)) ?? 0, 85.344, accuracy: 0.001)
    }

    func testRejectsTapsTooClose() {
        XCTAssertNil(ReferenceScale(referenceStart: .zero, referenceEnd: CGPoint(x: 5, y: 0), knownLengthCm: 8.56))
        let scale = ReferenceScale(referenceStart: .zero, referenceEnd: CGPoint(x: 100, y: 0), knownLengthCm: 10)!
        XCTAssertNil(scale.length(from: .zero, to: CGPoint(x: 3, y: 3)))
        XCTAssertNil(ReferenceScale(referenceStart: .zero, referenceEnd: CGPoint(x: 100, y: 0), knownLengthCm: 0))
    }

    func testReferenceLengths() {
        XCTAssertEqual(ReferenceObject.walletCard.lengthCm, 8.56)
        XCTAssertEqual(ReferenceObject.a4Paper.lengthCm, 29.7)
        XCTAssertEqual(ReferenceObject.letterPaper.lengthCm ?? 0, 11 * 2.54, accuracy: 0.001)
        XCTAssertNil(ReferenceObject.custom.lengthCm)
    }
}

final class ARMeasureStepTests: XCTestCase {
    func testMeasuresHeightThenWidthThenDepth() {
        var steps = MeasureSteps()
        // Height first: its top becomes the plane width and depth are measured on.
        XCTAssertEqual(steps.currentName, "height")
        XCTAssertFalse(steps.setEnd(distanceCm: 50))   // no start yet
        steps.setStart()
        XCTAssertTrue(steps.setEnd(distanceCm: 85))
        XCTAssertEqual(steps.currentName, "width")
        steps.setStart(); steps.setEnd(distanceCm: 200)
        XCTAssertEqual(steps.currentName, "depth")
        steps.setStart(); steps.setEnd(distanceCm: 90)
        XCTAssertTrue(steps.isDone)
        XCTAssertEqual(steps.results, [200, 90, 85])
        XCTAssertNil(steps.currentName)
    }

    func testIgnoresDoubleTaps() {
        var steps = MeasureSteps()
        steps.setStart()
        XCTAssertFalse(steps.setEnd(distanceCm: 0.3))
        XCTAssertTrue(steps.hasStart)   // still waiting for a real end
    }

    func testUndo() {
        var steps = MeasureSteps()
        steps.setStart(); steps.setEnd(distanceCm: 100)
        steps.setStart()
        steps.undo()
        XCTAssertFalse(steps.hasStart)
        XCTAssertEqual(steps.results, [100])
        steps.undo()
        XCTAssertTrue(steps.results.isEmpty)
    }

    func testDistanceInCentimeters() {
        let d = ARMeasure.distanceCm(SIMD3<Float>(0, 0, 0), SIMD3<Float>(0.3, 0.4, 0))
        XCTAssertEqual(d, 50, accuracy: 0.01)
    }
}

final class ARMeasureMathTests: XCTestCase {
    func testRayHitsTheFloor() throws {
        // Camera 1.5 m up, looking 45° down: meets the floor 1.5 m ahead.
        let point = try XCTUnwrap(ARMeasure.intersect(
            origin: SIMD3<Float>(0, 1.5, 0), direction: simd_normalize(SIMD3<Float>(0, -1, -1)),
            planePoint: .zero, normal: SIMD3<Float>(0, 1, 0)))
        XCTAssertEqual(point.y, 0, accuracy: 0.001)
        XCTAssertEqual(point.z, -1.5, accuracy: 0.001)
    }

    func testRayPointingUpMissesTheFloor() {
        XCTAssertNil(ARMeasure.intersect(
            origin: SIMD3<Float>(0, 1.5, 0), direction: SIMD3<Float>(0, 1, 0),
            planePoint: .zero, normal: SIMD3<Float>(0, 1, 0)))
    }

    func testHeightFromTheStandingLine() throws {
        // Floor point 2 m ahead; camera at 1 m aiming at a spot 0.8 m up the line.
        let base = SIMD3<Float>(0, 0, -2)
        let origin = SIMD3<Float>(0, 1, 0)
        let direction = simd_normalize(SIMD3<Float>(0, 0.8, -2) - origin)
        let top = try XCTUnwrap(ARMeasure.pointOnVerticalLine(base: base, origin: origin, direction: direction))
        XCTAssertEqual(ARMeasure.distanceCm(base, top), 80, accuracy: 0.5)
    }

    func testSmoothingMovesPartWay() {
        let moved = ARMeasure.smooth(SIMD3<Float>(0, 0, 0), toward: SIMD3<Float>(1, 0, 0), amount: 0.25)
        XCTAssertEqual(moved.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(ARMeasure.smooth(nil, toward: SIMD3<Float>(2, 0, 0)).x, 2)
    }

    func testFeaturePointOnlyNearTheAim() {
        let origin = SIMD3<Float>(0, 0, 0), direction = SIMD3<Float>(0, 0, -1)
        let points = [SIMD3<Float>(0.5, 0, -1), SIMD3<Float>(0.01, 0, -1.2)]
        XCTAssertEqual(ARMeasure.nearestFeaturePoint(points, origin: origin, direction: direction), points[1])
        XCTAssertNil(ARMeasure.nearestFeaturePoint([points[0]], origin: origin, direction: direction))
    }
}


final class MeasureStepsClarityTests: XCTestCase {
    func testRemeasureOneSize() {
        var steps = MeasureSteps()
        steps.setStart(); steps.setEnd(distanceCm: 85)    // height
        steps.setStart(); steps.setEnd(distanceCm: 200)   // width
        steps.setStart(); steps.setEnd(distanceCm: 90)    // depth
        XCTAssertTrue(steps.isDone)
        steps.remeasure(.depth)
        XCTAssertEqual(steps.current, .depth)
        XCTAssertEqual(steps.stepNumber, 3)
        steps.setStart(); steps.setEnd(distanceCm: 95)
        XCTAssertTrue(steps.isDone)
        XCTAssertEqual(steps.results, [200, 95, 85])
    }

    func testSpotsSwappedWidthAndDepth() {
        var steps = MeasureSteps()
        steps.setStart(); steps.setEnd(distanceCm: 80)    // height
        steps.setStart(); steps.setEnd(distanceCm: 90)    // measured depth as width
        steps.setStart(); steps.setEnd(distanceCm: 200)
        XCTAssertTrue(steps.looksSwapped)
        steps.swapWidthAndDepth()
        XCTAssertFalse(steps.looksSwapped)
        XCTAssertEqual(steps.value(.width), 200)
        XCTAssertEqual(steps.value(.depth), 90)
    }

    func testSquareThingsAreNotFlagged() {
        var steps = MeasureSteps()
        steps.setStart(); steps.setEnd(distanceCm: 45)    // height
        steps.setStart(); steps.setEnd(distanceCm: 40)
        steps.setStart(); steps.setEnd(distanceCm: 42)    // a stool: about square
        XCTAssertFalse(steps.looksSwapped)
    }

    func testMedianIgnoresOneShakyFrame() throws {
        let points = (0..<14).map { _ in SIMD3<Float>(1, 0, 2) } + [SIMD3<Float>(1.5, 0, 2)]
        let steady = try XCTUnwrap(ARMeasure.median(points))
        XCTAssertEqual(steady.x, 1, accuracy: 0.0001)
        XCTAssertNil(ARMeasure.median([]))
    }
}

final class TopPlaneTests: XCTestCase {
    func testAimingAtTheTopEdgeLandsOnTheItemNotBehindIt() throws {
        // A 6-inch-tall fan, 1 m in front of a phone held 1.2 m up. Aim at
        // the fan's near top edge: the top plane gives that point, while
        // the floor would give a point far behind the fan.
        let topY: Float = 0.15
        let origin = SIMD3<Float>(0, 1.2, 0)
        let edge = SIMD3<Float>(0, topY, -1)
        let direction = simd_normalize(edge - origin)
        let onTop = try XCTUnwrap(ARMeasure.intersect(origin: origin, direction: direction,
                                                      planePoint: SIMD3<Float>(0, topY, 0), normal: SIMD3<Float>(0, 1, 0)))
        XCTAssertEqual(simd_distance(onTop, edge), 0, accuracy: 0.001)
        let onFloor = try XCTUnwrap(ARMeasure.intersect(origin: origin, direction: direction,
                                                        planePoint: .zero, normal: SIMD3<Float>(0, 1, 0)))
        XCTAssertGreaterThan(simd_distance(onFloor, edge), 0.1)
    }
}


final class PhotoMeasuringTests: XCTestCase {
    /// Projects a point on a surface into a photo with a made-up camera
    /// tilted 35°, to test sizes from an angled photo.
    private func project(_ x: Double, _ y: Double) -> CGPoint {
        // Plane point (x, y) in cm → photo, a fixed perspective transform.
        let h: [Double] = [9.0, 1.5, 120, -0.8, 7.0, 300, 0.004, -0.0015, 1]
        let w = h[6] * x + h[7] * y + h[8]
        return CGPoint(x: (h[0] * x + h[1] * y + h[2]) / w, y: (h[3] * x + h[4] * y + h[5]) / w)
    }

    func testAngledPhotoStillGivesTheRightSize() throws {
        // A card at the origin, and a 50 × 80 cm chair front on the same surface.
        let card = [project(0, 0), project(8.56, 0), project(8.56, 5.398), project(0, 5.398)]
        let scale = try XCTUnwrap(PlaneScale(corners: card, sizeCm: (8.56, 5.398)))
        let width = try XCTUnwrap(scale.length(from: project(-10, 20), to: project(40, 20)))
        let height = try XCTUnwrap(scale.length(from: project(-10, 20), to: project(-10, 100)))
        XCTAssertEqual(width, 50, accuracy: 0.1)
        XCTAssertEqual(height, 80, accuracy: 0.1)
    }

    func testCornersCanStartAnywhereAndGoEitherWay() throws {
        let card = [project(8.56, 5.398), project(8.56, 0), project(0, 0), project(0, 5.398)]
        let scale = try XCTUnwrap(PlaneScale(corners: card, sizeCm: (8.56, 5.398)))
        XCTAssertEqual(try XCTUnwrap(scale.length(from: project(0, 30), to: project(60, 30))), 60, accuracy: 0.1)
    }

    func testStraightOnCardIsNotFlaggedAsAngled() throws {
        let square = [CGPoint(x: 100, y: 100), CGPoint(x: 185.6, y: 100), CGPoint(x: 185.6, y: 153.98), CGPoint(x: 100, y: 153.98)]
        XCTAssertFalse(try XCTUnwrap(PlaneScale(corners: square, sizeCm: (8.56, 5.398))).looksAngled)
        // Photographed steeply from below: the far edge looks much shorter.
        let skewed = [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100), CGPoint(x: 260, y: 160), CGPoint(x: 140, y: 160)]
        XCTAssertTrue(try XCTUnwrap(PlaneScale(corners: skewed, sizeCm: (8.56, 5.398))).looksAngled)
    }

    func testCardIsHiddenInTheSavedPhoto() throws {
        // A photo with fine detail (a checkerboard) where the card sits.
        let size = CGSize(width: 400, height: 300)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            for x in stride(from: 0, to: 400, by: 2) {
                for y in stride(from: 0, to: 300, by: 2) where (x + y) % 4 == 0 {
                    context.fill(CGRect(x: x, y: y, width: 2, height: 2))
                }
            }
        }
        let corners = [CGPoint(x: 150, y: 120), CGPoint(x: 236, y: 120), CGPoint(x: 236, y: 174), CGPoint(x: 150, y: 174)]
        let region = try XCTUnwrap(CardBlur.region(corners: corners, imageSize: size))
        for corner in corners { XCTAssertTrue(region.contains(corner)) }

        let hidden = CardBlur.hidingCard(in: original, corners: corners)
        let a = try XCTUnwrap(pixels(original)), b = try XCTUnwrap(pixels(hidden))
        // Inside the card's area the detail is gone; far away it's untouched.
        XCTAssertNotEqual(row(a, y: 147, from: 180, to: 200), row(b, y: 147, from: 180, to: 200))
        XCTAssertEqual(row(a, y: 10, from: 10, to: 40), row(b, y: 10, from: 10, to: 40))
    }

    private func pixels(_ image: UIImage) -> [UInt8]? {
        guard let cg = image.cgImage else { return nil }
        var data = [UInt8](repeating: 0, count: cg.width * cg.height)
        let gray = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: &data, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                      bytesPerRow: cg.width, space: gray, bitmapInfo: 0) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return data
    }

    private func row(_ data: [UInt8], y: Int, from: Int, to: Int) -> [UInt8] {
        Array(data[(y * 400 + from)..<(y * 400 + to)])
    }
}

final class PhotoViewportTests: XCTestCase {
    private let photo = CGSize(width: 4000, height: 3000)
    private let space = CGSize(width: 400, height: 400)

    func testRoundTripAtAnyZoomAndPan() {
        for (zoom, pan) in [(CGFloat(1), CGSize.zero), (3, CGSize(width: 120, height: -80)), (8, CGSize(width: -500, height: 300))] {
            let view = PhotoViewport(imageSize: photo, container: space, zoom: zoom, pan: pan)
            let corner = CGPoint(x: 1234, y: 2100)
            let back = view.imagePoint(fromScreen: view.screenPoint(fromImage: corner))
            XCTAssertEqual(back.x, corner.x, accuracy: 0.01)
            XCTAssertEqual(back.y, corner.y, accuracy: 0.01)
        }
    }

    func testZoomingMagnifiesAroundTheMiddle() {
        let whole = PhotoViewport(imageSize: photo, container: space, zoom: 1, pan: .zero)
        let zoomed = PhotoViewport(imageSize: photo, container: space, zoom: 4, pan: .zero)
        // The photo's middle stays in the middle of the view.
        XCTAssertEqual(zoomed.screenPoint(fromImage: CGPoint(x: 2000, y: 1500)), CGPoint(x: 200, y: 200))
        // 100 photo points apart: 4 times as far apart on screen when zoomed 4×.
        let a = CGPoint(x: 2000, y: 1500), b = CGPoint(x: 2100, y: 1500)
        XCTAssertEqual(zoomed.screenPoint(fromImage: b).x - zoomed.screenPoint(fromImage: a).x,
                       4 * (whole.screenPoint(fromImage: b).x - whole.screenPoint(fromImage: a).x), accuracy: 0.001)
    }

    func testPanCantDragThePhotoAway() {
        let view = PhotoViewport(imageSize: photo, container: space, zoom: 2, pan: .zero)
        let clamped = view.clamped(CGSize(width: 5000, height: -5000))
        // Fitted 400 × 300, zoomed 2× = 800 × 600: can move 200 sideways, 100 up or down.
        XCTAssertEqual(clamped.width, 200)
        XCTAssertEqual(clamped.height, -100)
        XCTAssertEqual(PhotoViewport(imageSize: photo, container: space, zoom: 1, pan: .zero).clamped(CGSize(width: 50, height: 50)), .zero)
    }

    func testGrabsTheNearestPointWithinReach() {
        let view = PhotoViewport(imageSize: photo, container: space, zoom: 1, pan: .zero)
        let points = [CGPoint(x: 1000, y: 1000), CGPoint(x: 3000, y: 2000)]
        let near = view.screenPoint(fromImage: points[1])
        XCTAssertEqual(view.nearestPoint(to: CGPoint(x: near.x + 10, y: near.y), in: points, within: 22), 1)
        XCTAssertNil(view.nearestPoint(to: CGPoint(x: near.x + 40, y: near.y), in: points, within: 22))
    }
}
