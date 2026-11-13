import XCTest
@testable import InteriorDesign

final class FlatMeasureTests: XCTestCase {
    func testFlatArtMeasuresWidthThenHeightWithDepthFilledIn() {
        var steps = MeasureSteps(flatWithDepth: 1)
        XCTAssertEqual(steps.stepCount, 2)
        XCTAssertEqual(steps.current, .width)
        XCTAssertEqual(steps.stepNumber, 1)
        steps.setStart()
        XCTAssertTrue(steps.setEnd(distanceCm: 61))
        XCTAssertEqual(steps.current, .height)
        XCTAssertEqual(steps.stepNumber, 2)
        steps.setStart()
        XCTAssertTrue(steps.setEnd(distanceCm: 91))
        XCTAssertTrue(steps.isDone)
        XCTAssertEqual(steps.results, [61, 1, 91], "width, depth, height")
    }

    func testRegularMeasuringIsUnchanged() {
        let steps = MeasureSteps()
        XCTAssertEqual(steps.stepCount, 3)
        XCTAssertEqual(steps.current, .height)
    }
}
