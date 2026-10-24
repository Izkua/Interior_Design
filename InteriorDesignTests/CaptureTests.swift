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
