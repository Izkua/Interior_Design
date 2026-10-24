import XCTest
@testable import InteriorDesign

final class PolygonGeometryTests: XCTestCase {
    /// 400 × 400 cm, clockwise on screen from the top-left.
    private let square = PlanGeometry.rectangleCorners(width: 400, length: 400)

    /// An L-shaped room: 400 wide, 400 deep, with the bottom-right
    /// 200 × 200 cut out. Corner 3 is the inside corner.
    private let lShape = [
        Point2D(x: 0, y: 0),
        Point2D(x: 400, y: 0),
        Point2D(x: 400, y: 200),
        Point2D(x: 200, y: 200),
        Point2D(x: 200, y: 400),
        Point2D(x: 0, y: 400)
    ]

    /// A 3-4-5 right triangle (scaled up 100×).
    private let triangle = [
        Point2D(x: 0, y: 0),
        Point2D(x: 400, y: 0),
        Point2D(x: 0, y: 300)
    ]

    /// Two walls cross in the middle, like a bow tie. Not a valid room.
    private let bowTie = [
        Point2D(x: 0, y: 0),
        Point2D(x: 400, y: 400),
        Point2D(x: 400, y: 0),
        Point2D(x: 0, y: 400)
    ]

    // MARK: Lengths, area, winding

    func testWallLength() {
        XCTAssertEqual(PolygonGeometry.wallLength(from: triangle[1], to: triangle[2]), 500, accuracy: 0.001)
    }

    func testAreas() {
        XCTAssertEqual(PolygonGeometry.area(square), 160_000, accuracy: 0.001)
        XCTAssertEqual(PolygonGeometry.area(lShape), 120_000, accuracy: 0.001)
        XCTAssertEqual(PolygonGeometry.area(triangle), 60_000, accuracy: 0.001)
    }

    func testWindingOrder() {
        XCTAssertTrue(PolygonGeometry.isClockwise(square))
        let backwards = Array(square.reversed())
        XCTAssertFalse(PolygonGeometry.isClockwise(backwards))

        let fixed = PolygonGeometry.clockwise(backwards)
        XCTAssertTrue(PolygonGeometry.isClockwise(fixed))
        XCTAssertEqual(fixed.first, backwards.first)
        XCTAssertEqual(PolygonGeometry.area(fixed), 160_000, accuracy: 0.001)
    }

    // MARK: Angles

    func testSquareCornersAreRightAngles() {
        for i in 0..<4 {
            XCTAssertEqual(PolygonGeometry.interiorAngle(at: i, corners: square), 90, accuracy: 0.001)
        }
    }

    func testLShapeHasOneInsideCorner() {
        let angles = (0..<6).map { PolygonGeometry.interiorAngle(at: $0, corners: lShape) }
        for (i, angle) in angles.enumerated() {
            XCTAssertEqual(angle, i == 3 ? 270 : 90, accuracy: 0.001, "corner \(i)")
        }
        // Any simple polygon's angles add up to (corners − 2) × 180.
        XCTAssertEqual(angles.reduce(0, +), 720, accuracy: 0.001)
    }

    func testAnglesDoNotDependOnWinding() {
        let backwards = Array(lShape.reversed())
        // Corner 3 of lShape is corner 2 of the reversed list.
        XCTAssertEqual(PolygonGeometry.interiorAngle(at: 2, corners: backwards), 270, accuracy: 0.001)
    }

    func testTriangleAngles() {
        let angles = (0..<3).map { PolygonGeometry.interiorAngle(at: $0, corners: triangle) }
        XCTAssertEqual(angles[0], 90, accuracy: 0.001)
        XCTAssertEqual(angles.reduce(0, +), 180, accuracy: 0.001)
    }

    func testSnappedAngle() {
        XCTAssertEqual(PolygonGeometry.snappedAngle(88), 90)
        XCTAssertEqual(PolygonGeometry.snappedAngle(47), 45)
        XCTAssertEqual(PolygonGeometry.snappedAngle(128), 135)
        XCTAssertEqual(PolygonGeometry.snappedAngle(176), 180)
        XCTAssertEqual(PolygonGeometry.snappedAngle(268), 270)
        XCTAssertEqual(PolygonGeometry.snappedAngle(318), 315)
    }

    func testSnapCornerSquaresUpACorner() {
        // Drag the bottom-right corner of the square slightly off.
        let snapped = PolygonGeometry.snapCorner(2, to: Point2D(x: 409, y: 393), corners: square)
        var moved = square
        moved[2] = snapped
        for i in 0..<4 {
            XCTAssertEqual(PolygonGeometry.interiorAngle(at: i, corners: moved), 90, accuracy: 0.01, "corner \(i)")
        }
    }

    func testSnapCornerKeepsLShapeInsideCornerSquare() {
        let snapped = PolygonGeometry.snapCorner(3, to: Point2D(x: 206, y: 195), corners: lShape)
        var moved = lShape
        moved[3] = snapped
        XCTAssertEqual(PolygonGeometry.interiorAngle(at: 3, corners: moved), 270, accuracy: 0.01)
        XCTAssertEqual(PolygonGeometry.interiorAngle(at: 2, corners: moved), 90, accuracy: 0.01)
        XCTAssertEqual(PolygonGeometry.interiorAngle(at: 4, corners: moved), 90, accuracy: 0.01)
    }

    // MARK: Shape checks

    func testSimpleShapes() {
        XCTAssertTrue(PolygonGeometry.isSimple(square))
        XCTAssertTrue(PolygonGeometry.isSimple(lShape))
        XCTAssertTrue(PolygonGeometry.isSimple(triangle))
    }

    func testBowTieIsNotSimple() {
        XCTAssertFalse(PolygonGeometry.isSimple(bowTie))
    }

    func testTooFewCornersOrZeroWallIsNotSimple() {
        XCTAssertFalse(PolygonGeometry.isSimple(Array(square.prefix(2))))
        XCTAssertFalse(PolygonGeometry.isSimple([square[0], square[0], square[1], square[2]]))
    }

    // MARK: Measured walls

    func testSettingWallLengthMovesFarCorner() {
        let result = PolygonGeometry.settingWallLength(0, to: 500, corners: square)
        XCTAssertEqual(result[0], square[0])
        XCTAssertEqual(result[1].x, 500, accuracy: 0.001)
        XCTAssertEqual(result[1].y, 0, accuracy: 0.001)
        XCTAssertEqual(Array(result[2...]), Array(square[2...]))
    }

    func testMatchingLengthsClose() {
        let lengths = (0..<6).map { PlanGeometry.wallLength($0, corners: lShape) }
        XCTAssertNil(PolygonGeometry.closureCheck(corners: lShape, lengths: lengths))
    }

    func testNearMissIsWithinTolerance() {
        // Measuring tape slop of 1 cm should not bother anyone.
        XCTAssertNil(PolygonGeometry.closureCheck(corners: square, lengths: [400, 401, 400, 400]))
    }

    func testMismatchNamesWallAndFix() throws {
        // Top wall measured 412 cm, but the bottom wall says 400.
        let check = try XCTUnwrap(PolygonGeometry.closureCheck(corners: square, lengths: [412, 400, 400, 400]))
        XCTAssertEqual(check.gap, 12, accuracy: 0.001)
        XCTAssertTrue([0, 2].contains(check.wall), "a horizontal wall is off")
        XCTAssertEqual(abs(check.difference), 12, accuracy: 0.001)

        // Applying the suggestion closes the room.
        var fixed = [412.0, 400, 400, 400]
        fixed[check.wall] = check.suggestedLength
        XCTAssertNil(PolygonGeometry.closureCheck(corners: square, lengths: fixed))
    }

    func testLShapeMismatchPointsAtHorizontalWall() throws {
        var lengths = (0..<6).map { PlanGeometry.wallLength($0, corners: lShape) }
        lengths[2] = 230  // measured 30 cm too long
        let check = try XCTUnwrap(PolygonGeometry.closureCheck(corners: lShape, lengths: lengths))
        XCTAssertEqual(check.gap, 30, accuracy: 0.001)
        XCTAssertEqual(abs(check.difference), 30, accuracy: 0.001)
        // Walls 0, 2, and 4 run left to right; any of them explains it.
        XCTAssertTrue([0, 2, 4].contains(check.wall))
    }

    func testClosedOutlineSpreadsTheGap() {
        let lengths: [Double] = [410, 400, 400, 400]
        let outline = PolygonGeometry.closedOutline(corners: square, lengths: lengths)
        XCTAssertEqual(outline.count, 4)
        XCTAssertEqual(outline[0], square[0])
        XCTAssertTrue(PolygonGeometry.isSimple(outline))
        // Every wall ends up within a few cm of its measurement.
        for i in 0..<4 {
            XCTAssertEqual(PlanGeometry.wallLength(i, corners: outline), lengths[i], accuracy: 6, "wall \(i)")
        }
    }
}
