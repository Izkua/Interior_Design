import XCTest
@testable import InteriorDesign

final class GeometryTests: XCTestCase {
    private let corners = PlanGeometry.rectangleCorners(width: 400, length: 300)

    func testWallLengths() {
        XCTAssertEqual(PlanGeometry.wallLength(0, corners: corners), 400, accuracy: 0.001)
        XCTAssertEqual(PlanGeometry.wallLength(1, corners: corners), 300, accuracy: 0.001)
    }

    func testNearestWallSnapsToTop() {
        let hit = PlanGeometry.nearestWall(to: Point2D(x: 100, y: -20), corners: corners)
        XCTAssertEqual(hit.wall, 0)
        XCTAssertEqual(hit.offset, 100, accuracy: 0.001)
    }

    func testClampKeepsFeatureInsideWall() {
        XCTAssertEqual(PlanGeometry.clampOffset(0, width: 90, wallLength: 400), 45, accuracy: 0.001)
        XCTAssertEqual(PlanGeometry.clampOffset(999, width: 90, wallLength: 400), 355, accuracy: 0.001)
    }

    func testFreeSpotAvoidsTakenSpace() {
        // A 400 cm top wall with a window covering 0 to 200 cm.
        let spot = PlanGeometry.freeSpot(
            width: 90,
            preferredWalls: [0],
            corners: corners,
            taken: [(wall: 0, offset: 100, width: 200)]
        )
        XCTAssertEqual(spot.wall, 0)
        XCTAssertEqual(spot.offset, 300, accuracy: 0.001)
    }

    func testFreeSpotMovesToNextWallWhenFull() {
        let spot = PlanGeometry.freeSpot(
            width: 90,
            preferredWalls: [0, 1],
            corners: corners,
            taken: [(wall: 0, offset: 200, width: 400)]
        )
        XCTAssertEqual(spot.wall, 1)
        XCTAssertEqual(spot.offset, 150, accuracy: 0.001)
    }
}
