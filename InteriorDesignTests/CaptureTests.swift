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

    func testCreditCardScale() throws {
        // A card spanning 100 points means 0.0856 cm per point.
        let scale = try XCTUnwrap(ReferenceScale(
            referenceStart: CGPoint(x: 0, y: 0), referenceEnd: CGPoint(x: 100, y: 0),
            knownLengthCm: ReferenceObject.creditCard.lengthCm!
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
        XCTAssertEqual(ReferenceObject.creditCard.lengthCm, 8.56)
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

