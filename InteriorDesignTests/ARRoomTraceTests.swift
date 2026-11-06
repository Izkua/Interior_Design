import XCTest
import simd
@testable import InteriorDesign

/// Turning corners tapped on the floor (in meters) into a room outline.
final class ARRoomTraceTests: XCTestCase {
    // A 4 × 3 m room, traced at floor height 0 (y), going around.
    private let room: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(4, 0, 0), SIMD3(4, 0, 3), SIMD3(0, 0, 3)]

    func testFourCornersMakeTheRightRoom() throws {
        let draft = try XCTUnwrap(ARRoomTrace.draft(corners: room))
        XCTAssertEqual(draft.corners.count, 4)
        let xs = draft.corners.map(\.x), ys = draft.corners.map(\.y)
        XCTAssertEqual(xs.max()! - xs.min()!, 400, accuracy: 0.5)
        XCTAssertEqual(ys.max()! - ys.min()!, 300, accuracy: 0.5)
        XCTAssertTrue(draft.closed)
    }

    func testWallsAreMarkedForChecking() throws {
        let draft = try XCTUnwrap(ARRoomTrace.draft(corners: room))
        XCTAssertTrue(draft.walls.allSatisfy { $0.seen && $0.confidence < 1 })
    }

    func testTracingTheOtherWayRoundGivesTheSameRoom() throws {
        let draft = try XCTUnwrap(ARRoomTrace.draft(corners: room.reversed()))
        let xs = draft.corners.map(\.x)
        XCTAssertEqual(xs.max()! - xs.min()!, 400, accuracy: 0.5)
    }

    func testTooFewCornersOrCrossingWallsAreRejected() {
        XCTAssertNil(ARRoomTrace.draft(corners: Array(room.prefix(2))))
        // Corners in a bow-tie order: walls cross.
        let crossed: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(4, 0, 3), SIMD3(4, 0, 0), SIMD3(0, 0, 3)]
        XCTAssertNil(ARRoomTrace.draft(corners: crossed))
    }

    func testAimingBackAtTheFirstCornerClosesTheRoom() {
        XCTAssertFalse(ARRoomTrace.closes(Array(room.prefix(2)), with: SIMD3(0.1, 0, 0.1)))   // need 3 corners first
        XCTAssertTrue(ARRoomTrace.closes(Array(room.prefix(3)), with: SIMD3(0.1, 0.02, 0.1)))
        XCTAssertFalse(ARRoomTrace.closes(Array(room.prefix(3)), with: SIMD3(0, 0, 3)))
    }

    func testWallLengthIgnoresHeight() {
        XCTAssertEqual(ARRoomTrace.lengthCm(SIMD3(0, 0, 0), SIMD3(3, 0.2, 4)), 500, accuracy: 0.1)
    }

    func testADoorLandsOnTheRightWall() throws {
        // A 0.9 m door on the far wall (z = 3), from x = 1 to x = 1.9.
        let door = ARRoomTrace.Opening(kind: .door, a: SIMD3(1, 0, 3), b: SIMD3(1.9, 0, 3))
        let draft = try XCTUnwrap(ARRoomTrace.draft(corners: room, openings: [door]))
        let feature = try XCTUnwrap(draft.features.first)
        XCTAssertEqual(feature.kind, .door)
        XCTAssertEqual(feature.widthCm, 90, accuracy: 1)
    }
}

final class SquareCornerTests: XCTestCase {
    private func angles(_ c: [Point2D]) -> [Double] {
        c.indices.map { PolygonGeometry.interiorAngle(at: $0, corners: c) }
    }

    func testNewWallsSnapToRightAngles() {
        let corners: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(4, 0, 0)]
        // Aimed 3 m "down" but drifting 0.25 m sideways (about 5° off).
        let next = ARRoomTrace.snapped(SIMD3(4.25, 0, 3), after: corners)
        XCTAssertEqual(next.point.x, 4, accuracy: 0.001)
        XCTAssertEqual(next.point.z, 3.01, accuracy: 0.01)   // keeps its length
        XCTAssertEqual(next.turn, 90)
    }

    func testFirstTwoCornersArePlacedAsAimed() {
        let next = ARRoomTrace.snapped(SIMD3(3.9, 0, 0.3), after: [SIMD3(0, 0, 0)])
        XCTAssertEqual(next.point, SIMD3(3.9, 0, 0.3))
        XCTAssertNil(next.turn)
    }

    func testFortyFiveDegreeWallSnapsToFortyFive() {
        let corners: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(4, 0, 0)]
        // About 41° off the first wall.
        let next = ARRoomTrace.snapped(SIMD3(5.5, 0, 1.3), after: corners)
        let d = next.point - corners[1]
        XCTAssertEqual(atan2(d.z, d.x) * 180 / .pi, 45, accuracy: 0.01)
        XCTAssertEqual(next.turn, 45)
    }

    func testOddAngleIsLeftAlone() {
        let corners: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(4, 0, 0)]
        // About 25° — not near 0°, 45° or 90°.
        let aimed = SIMD3<Float>(4 + 2 * cos(25 * .pi / 180), 0, 2 * sin(25 * .pi / 180))
        let next = ARRoomTrace.snapped(aimed, after: corners)
        XCTAssertEqual(next.point, aimed)
        XCTAssertNil(next.turn)
    }

    func testNoisyRectangleBecomesExactRectangle() throws {
        // A 400 × 300 cm room traced by hand, every corner a little off.
        let noisy = [Point2D(x: 0, y: 0), Point2D(x: 405, y: 8), Point2D(x: 390, y: 310), Point2D(x: -10, y: 295)]
        let square = try XCTUnwrap(RoomStraightener.straightened(noisy))
        for a in angles(square) { XCTAssertEqual(a, 90, accuracy: 0.01) }
        let walls = (0..<4).map { PlanGeometry.wallLength($0, corners: square) }
        XCTAssertEqual(walls[0], walls[2], accuracy: 0.01)   // opposite walls match
        XCTAssertEqual(walls[1], walls[3], accuracy: 0.01)
        XCTAssertEqual(walls[0], 400, accuracy: 10)
        XCTAssertEqual(walls[1], 300, accuracy: 10)
    }

    func testNoisyLShapeBecomesCleanL() throws {
        let noisy = [Point2D(x: 0, y: 0), Point2D(x: 400, y: 5), Point2D(x: 402, y: 200), Point2D(x: 200, y: 203),
                     Point2D(x: 197, y: 400), Point2D(x: 3, y: 398)]
        let clean = try XCTUnwrap(RoomStraightener.straightened(noisy))
        XCTAssertEqual(clean.count, 6)
        let a = angles(clean)
        XCTAssertEqual(a.filter { abs($0 - 270) < 0.01 }.count, 1)
        XCTAssertEqual(a.filter { abs($0 - 90) < 0.01 }.count, 5)
    }

    func testRealFortyFiveWallIsKeptWithoutFortyFiveSnapping() throws {
        // A room with one corner cut off at 45°, traced slightly off.
        let noisy = [Point2D(x: 0, y: 0), Point2D(x: 300, y: 4), Point2D(x: 400, y: 100), Point2D(x: 398, y: 300), Point2D(x: 2, y: 302)]
        let clean = try XCTUnwrap(RoomStraightener.straightened(noisy, allow45: false))
        let cut = atan2(clean[2].y - clean[1].y, clean[2].x - clean[1].x) * 180 / .pi
        XCTAssertEqual(cut, 43.7, accuracy: 1.5)   // still a diagonal, not squared away
        // And with 45° snapping it becomes exactly 45°.
        let snapped = try XCTUnwrap(RoomStraightener.straightened(noisy))
        // (Angles are measured from the first wall, which is slightly tilted.)
        let first = atan2(snapped[1].y - snapped[0].y, snapped[1].x - snapped[0].x)
        XCTAssertEqual((atan2(snapped[2].y - snapped[1].y, snapped[2].x - snapped[1].x) - first) * 180 / .pi, 45, accuracy: 0.01)
    }

    func testAlreadySquareRoomNeedsNothing() {
        XCTAssertNil(RoomStraightener.straightened([Point2D(x: 0, y: 0), Point2D(x: 400, y: 0), Point2D(x: 400, y: 300), Point2D(x: 0, y: 300)]))
    }

    func testDraftKeepsDoorsOnTheirWalls() throws {
        let noisy: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(4.05, 0, 0.08), SIMD3(3.9, 0, 3.1), SIMD3(-0.1, 0, 2.95)]
        let door = ARRoomTrace.Opening(kind: .door, a: SIMD3(1.5, 0, 0.03), b: SIMD3(2.4, 0, 0.05))
        let draft = try XCTUnwrap(ARRoomTrace.draft(corners: noisy, openings: [door]))
        let straight = try XCTUnwrap(RoomStraightener.straightened(draft))
        XCTAssertEqual(straight.features.count, 1)
        let f = straight.features[0]
        XCTAssertLessThanOrEqual(f.offsetCm, PlanGeometry.wallLength(f.wall, corners: straight.corners))
        XCTAssertEqual(straight.corners.map(\.x).min()!, 0, accuracy: 0.001)
        XCTAssertEqual(straight.corners.map(\.y).min()!, 0, accuracy: 0.001)
        for a in angles(straight.corners) { XCTAssertEqual(a, 90, accuracy: 0.01) }
    }
}
