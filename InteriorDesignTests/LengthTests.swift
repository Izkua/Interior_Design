import XCTest
@testable import InteriorDesign

final class LengthTests: XCTestCase {
    func testParsesFeetAndInches() {
        let cm = Length.parse("12' 6\"", system: .imperial)
        XCTAssertNotNil(cm)
        XCTAssertEqual(cm ?? 0, 381, accuracy: 0.5)
    }

    func testParsesMetric() {
        XCTAssertEqual(Length.parse("3.5 m", system: .metric) ?? 0, 350, accuracy: 0.5)
        XCTAssertEqual(Length.parse("420 cm", system: .metric) ?? 0, 420, accuracy: 0.5)
    }

    func testRejectsGarbage() {
        XCTAssertNil(Length.parse("abc", system: .imperial))
    }

    func testFormatRoundTrip() {
        let text = Length.format(381, system: .imperial)
        XCTAssertEqual(Length.parse(text, system: .imperial) ?? 0, 381, accuracy: 1.5)
    }

    func testBareMetricNumbers() {
        // Small numbers are meters, big ones are centimeters.
        XCTAssertEqual(Length.parse("3.8", system: .metric) ?? 0, 380, accuracy: 0.5)
        XCTAssertEqual(Length.parse("380", system: .metric) ?? 0, 380, accuracy: 0.5)
    }

    func testBareImperialNumberIsFeet() {
        XCTAssertEqual(Length.parse("12", system: .imperial) ?? 0, 365.76, accuracy: 0.5)
    }

    func testRejectsZero() {
        XCTAssertNil(Length.parse("0", system: .metric))
    }

    func testThinThingsDontShowZero() {
        // A rug about 1 cm thick.
        XCTAssertEqual(Length.formatDimensions(height: 1, width: 69, depth: 117, system: .imperial), "<1 × 27 × 46 in")
        XCTAssertEqual(Length.formatDimensions(height: 0.3, width: 69, depth: 117, system: .metric), "<1 × 69 × 117 cm")
        // Height × width × depth.
        XCTAssertEqual(Length.formatDimensions(height: 80, width: 100, depth: 50, system: .metric), "80 × 100 × 50 cm")
        // No depth listed (a poster): just height × width.
        XCTAssertEqual(Length.formatDimensions(height: 24 * 2.54, width: 36 * 2.54, depth: nil, system: .imperial), "24 × 36 in")
    }
}
