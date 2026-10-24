import XCTest
@testable import InteriorDesign

/// The room model as edited by the advanced builder.
final class CustomRoomTests: XCTestCase {
    private func makeCustomRoom() -> Room {
        let room = Room(name: "Test", width: 400, length: 300)
        room.setShape(.custom)
        return room
    }

    /// Every feature sits fully on an existing wall.
    private func assertFeaturesValid(_ room: Room, file: StaticString = #filePath, line: UInt = #line) {
        for feature in room.features {
            XCTAssertTrue(room.corners.indices.contains(feature.wall), "wall \(feature.wall) exists", file: file, line: line)
            let length = PlanGeometry.wallLength(feature.wall, corners: room.corners)
            XCTAssertLessThanOrEqual(feature.widthCm, length + 0.001, file: file, line: line)
            XCTAssertGreaterThanOrEqual(feature.offsetCm, feature.widthCm / 2 - 0.001, file: file, line: line)
            XCTAssertLessThanOrEqual(feature.offsetCm, length - feature.widthCm / 2 + 0.001, file: file, line: line)
        }
    }

    // MARK: Shape changes

    func testConvertingToCustomKeepsCorners() {
        let room = Room(name: "Test", width: 400, length: 300)
        let before = room.corners
        room.setShape(.custom)
        XCTAssertEqual(room.shape, .custom)
        XCTAssertEqual(room.corners, before)
    }

    func testBackToRectangleUsesOverallSize() {
        let room = makeCustomRoom()
        room.insertCorner(at: Point2D(x: 200, y: 360))
        room.setWallLength(0, to: 420)
        room.setShape(.rectangle)
        XCTAssertEqual(room.corners.count, 4)
        XCTAssertEqual(room.width, 420, accuracy: 0.001)
        XCTAssertTrue(room.measurements.isEmpty)
    }

    // MARK: Corners

    func testMoveCornerKeepsFeaturesOnTheirWalls() {
        let room = makeCustomRoom()
        let window = room.addFeature(.window)
        room.moveCorner(1, to: Point2D(x: 150, y: 0))  // shrink the top wall a lot
        let moved = room.features.first { $0.id == window.id }!
        XCTAssertEqual(moved.wall, window.wall)
        assertFeaturesValid(room)
    }

    func testInsertCornerSplitsNearestWall() {
        let room = makeCustomRoom()
        let index = room.insertCorner(at: Point2D(x: 200, y: 340))  // just below the bottom wall
        XCTAssertEqual(room.corners.count, 5)
        XCTAssertEqual(index, 3)
        XCTAssertEqual(room.corners[3], Point2D(x: 200, y: 340))
    }

    func testInsertCornerKeepsFeaturePosition() {
        let room = makeCustomRoom()
        // A window on the right wall (wall 1), which becomes wall 2 after
        // a corner is added on the top wall.
        room.features = [FixedFeature(kind: .window, wall: 1, offsetCm: 150, widthCm: 100)]
        room.insertCorner(at: Point2D(x: 200, y: -10))
        XCTAssertEqual(room.features[0].wall, 2)
        XCTAssertEqual(room.features[0].offsetCm, 150, accuracy: 0.001)
    }

    func testRemoveCornerMovesFeatureOffMergedWall() {
        let room = makeCustomRoom()
        room.insertCorner(at: Point2D(x: 200, y: 360))  // a bump on the bottom wall
        room.features = [FixedFeature(kind: .door, wall: 2, offsetCm: 60, widthCm: 90)]
        XCTAssertTrue(room.removeCorner(3))
        XCTAssertEqual(room.corners.count, 4)
        assertFeaturesValid(room)
    }

    func testCannotGoBelowThreeCorners() {
        let room = makeCustomRoom()
        XCTAssertTrue(room.removeCorner(0))
        XCTAssertFalse(room.removeCorner(0))
        XCTAssertEqual(room.corners.count, 3)
    }

    // MARK: Measurements

    func testSetWallLengthRecordsMeasurement() {
        let room = makeCustomRoom()
        room.setWallLength(0, to: 450)
        XCTAssertEqual(room.measuredLength(0), 450)
        XCTAssertEqual(PlanGeometry.wallLength(0, corners: room.corners), 450, accuracy: 0.001)
    }

    func testMeasurementsRenumberWhenCornersChange() {
        let room = makeCustomRoom()
        room.setWallLength(2, to: 400)  // bottom wall
        room.insertCorner(at: Point2D(x: 200, y: -10))  // splits the top wall
        XCTAssertNil(room.measuredLength(2))
        XCTAssertEqual(room.measuredLength(3), 400)

        room.removeCorner(1)  // joins walls 0 and 1 back together
        XCTAssertEqual(room.measuredLength(2), 400)
    }

    func testMismatchIsFoundAndFixed() throws {
        let room = makeCustomRoom()
        for (wall, length) in [400.0, 300, 400, 300].enumerated() {
            room.setWallLength(wall, to: length)
        }
        XCTAssertNil(room.closureCheck)

        // Retyping the top wall as 500 cm moves the top-right corner, so
        // the right wall is now drawn about 316 cm but was measured 300.
        room.setWallLength(0, to: 500)
        let check = try XCTUnwrap(room.closureCheck)
        XCTAssertGreaterThan(check.gap, 10)

        room.applyFix(check)
        XCTAssertNil(room.closureCheck)
        XCTAssertTrue(PolygonGeometry.isSimple(room.corners))
    }

    func testRectanglesNeverReportMismatch() {
        let room = Room(name: "Test", width: 400, length: 300)
        room.measurements = [WallMeasurement(wall: 0, lengthCm: 999)]
        XCTAssertNil(room.closureCheck)
    }

    // MARK: Undo

    func testOutlineRoundTrip() {
        let room = makeCustomRoom()
        let before = room.outline
        room.insertCorner(at: Point2D(x: 200, y: 360))
        room.setWallLength(0, to: 450)
        room.outline = before
        XCTAssertEqual(room.outline, before)
    }

    func testEditHistory() {
        var history = EditHistory<Int>()
        XCTAssertFalse(history.canUndo)

        history.record(1)  // was 1, now 2
        history.record(2)  // was 2, now 3
        XCTAssertEqual(history.undo(current: 3), 2)
        XCTAssertEqual(history.undo(current: 2), 1)
        XCTAssertNil(history.undo(current: 1))
        XCTAssertEqual(history.redo(current: 1), 2)

        history.record(2)  // a new edit clears redo
        XCTAssertFalse(history.canRedo)
    }

    func testEditHistoryLimit() {
        var history = EditHistory<Int>()
        history.limit = 3
        for value in 0..<10 { history.record(value) }
        XCTAssertEqual(history.undoStack, [7, 8, 9])
    }
}
