import XCTest
@testable import InteriorDesign

final class RoomScanTests: XCTestCase {
    private func parse(_ json: String) throws -> RoomDraft {
        try RoomDraftParser.parse(Data(json.utf8))
    }

    // MARK: Parsing

    func testParsesFullDraft() throws {
        let draft = try parse("""
        {"version":1,
         "corners":[{"x":100,"y":50},{"x":520,"y":50},{"x":520,"y":410},{"x":100,"y":410}],
         "walls":[{"seen":true,"confidence":0.9},{"seen":true,"confidence":0.4},{"seen":true,"confidence":0.8},{"seen":false}],
         "features":[{"kind":"door","wall":2,"offsetCm":80,"widthCm":90}],
         "closed":true,
         "next":{"direction":"left","hint":"Turn left."}}
        """)
        // Moved so the top-left corner is at 0,0.
        XCTAssertEqual(draft.corners.first, Point2D(x: 0, y: 0))
        XCTAssertEqual(draft.corners.count, 4)
        XCTAssertEqual(draft.uncertainWalls, [1, 3])
        XCTAssertFalse(draft.isComplete)          // wall 3 wasn't seen
        XCTAssertEqual(draft.features.first?.kind, .door)
        XCTAssertEqual(draft.nextDirection, .left)
        XCTAssertEqual(draft.nextHint, "Turn left.")
    }

    func testOnlyCornersIsEnough() throws {
        let draft = try parse(#"{"corners":[{"x":0,"y":0},{"x":300,"y":0},{"x":300,"y":300}]}"#)
        XCTAssertEqual(draft.walls.count, 3)
        // Walls without info count as not seen, so they're flagged.
        XCTAssertEqual(draft.uncertainWalls, [0, 1, 2])
        XCTAssertTrue(draft.closed)
    }

    func testCounterclockwiseIsFixed() throws {
        // A rectangle listed the other way round, with a door on its last wall.
        let draft = try parse("""
        {"corners":[{"x":0,"y":0},{"x":0,"y":300},{"x":400,"y":300},{"x":400,"y":0}],
         "walls":[{"seen":true,"confidence":0.9},{"seen":true,"confidence":0.9},{"seen":true,"confidence":0.9},{"seen":true,"confidence":0.3}],
         "features":[{"kind":"window","wall":3,"offsetCm":100,"widthCm":120}]}
        """)
        XCTAssertTrue(PolygonGeometry.isClockwise(draft.corners))
        // Old wall 3 ran (400,0) → (0,0); it's now wall 0, running (0,0) → (400,0).
        XCTAssertEqual(draft.uncertainWalls, [0])
        let window = try XCTUnwrap(draft.features.first)
        XCTAssertEqual(window.wall, 0)
        XCTAssertEqual(window.offsetCm, 300, accuracy: 0.001)   // 100 cm from the other end
    }

    func testRejectsBadDrafts() {
        XCTAssertThrowsError(try parse("not json")) { XCTAssertEqual($0 as? RoomDraftError, .notJSON) }
        XCTAssertThrowsError(try parse(#"{"corners":[{"x":0,"y":0},{"x":1,"y":1}]}"#)) {
            XCTAssertEqual($0 as? RoomDraftError, .tooFewCorners)
        }
        XCTAssertThrowsError(try parse(#"{"corners":[{"x":0,"y":0},{"x":90000,"y":0},{"x":0,"y":300}]}"#)) {
            XCTAssertEqual($0 as? RoomDraftError, .badNumbers)
        }
        // A bow tie: two walls cross.
        XCTAssertThrowsError(try parse(#"{"corners":[{"x":0,"y":0},{"x":400,"y":400},{"x":400,"y":0},{"x":0,"y":400}]}"#)) {
            XCTAssertEqual($0 as? RoomDraftError, .crossingWalls)
        }
    }

    func testDropsBadFeaturesAndClampsConfidence() throws {
        let draft = try parse("""
        {"corners":[{"x":0,"y":0},{"x":300,"y":0},{"x":300,"y":300},{"x":0,"y":300}],
         "walls":[{"seen":true,"confidence":7},{"seen":true,"confidence":-1}],
         "features":[{"kind":"door","wall":9,"offsetCm":50},{"kind":"skylight","wall":0,"offsetCm":50},{"kind":"outlet","wall":1,"offsetCm":40}]}
        """)
        XCTAssertEqual(draft.walls[0].confidence, 1)
        XCTAssertEqual(draft.walls[1].confidence, 0)
        XCTAssertEqual(draft.features.map(\.kind), [.outlet])
        XCTAssertEqual(draft.features[0].widthCm, FeatureKind.outlet.defaultWidthCm)
    }

    // MARK: The loop

    func testLoopStopsWhenCompleteOrAtTen() throws {
        let open = try parse(#"{"corners":[{"x":0,"y":0},{"x":300,"y":0},{"x":300,"y":300}],"closed":false}"#)
        XCTAssertFalse(ScanLoop.isFinished(draft: nil, photoCount: 3))
        XCTAssertFalse(ScanLoop.isFinished(draft: open, photoCount: 9))
        XCTAssertTrue(ScanLoop.isFinished(draft: open, photoCount: 10))
        let done = try parse("""
        {"corners":[{"x":0,"y":0},{"x":300,"y":0},{"x":300,"y":300}],
         "walls":[{"seen":true},{"seen":true},{"seen":true}],"closed":true}
        """)
        XCTAssertTrue(ScanLoop.isFinished(draft: done, photoCount: 3))
    }

    func testHintsGuideTheNextPhoto() throws {
        XCTAssertEqual(ScanLoop.nextHint(draft: nil, photoCount: 0).direction, .ahead)
        XCTAssertEqual(ScanLoop.nextHint(draft: nil, photoCount: 1).direction, .right)
        let draft = try parse(#"{"corners":[{"x":0,"y":0},{"x":300,"y":0},{"x":300,"y":300}],"closed":false,"next":{"direction":"behind","hint":"Turn around."}}"#)
        XCTAssertEqual(ScanLoop.nextHint(draft: draft, photoCount: 2).text, "Turn around.")
        XCTAssertEqual(ScanLoop.nextHint(draft: draft, photoCount: 10).direction, .done)
    }

    // MARK: Into the room

    func testApplyingDraftMarksUnsureWalls() throws {
        let room = Room(name: "Test", width: 400, length: 400)
        let draft = try parse("""
        {"corners":[{"x":0,"y":0},{"x":420,"y":0},{"x":420,"y":360},{"x":0,"y":360}],
         "walls":[{"seen":true,"confidence":0.9},{"seen":true,"confidence":0.3},{"seen":true,"confidence":0.9},{"seen":true,"confidence":0.9}],
         "features":[{"kind":"door","wall":2,"offsetCm":400,"widthCm":90}]}
        """)
        room.apply(draft)
        XCTAssertEqual(room.shape, .custom)
        XCTAssertEqual(room.width, 420, accuracy: 0.001)
        XCTAssertEqual(room.uncertainWalls, [1])
        // The door was too close to the end; it's moved fully onto the wall.
        XCTAssertLessThanOrEqual(room.features[0].offsetCm, 420 - 45 + 0.001)

        // Typing the real length clears the warning for that wall.
        room.setWallLength(1, to: 355)
        XCTAssertTrue(room.uncertainWalls.isEmpty)
    }

    func testUnsureWallsFollowCornerEdits() throws {
        let room = Room(name: "Test", width: 400, length: 400)
        room.setShape(.custom)
        room.uncertainWalls = [2]
        room.insertCorner(at: Point2D(x: 200, y: -10))   // splits wall 0
        XCTAssertEqual(room.uncertainWalls, [3])
        room.insertCorner(at: Point2D(x: 410, y: 300))   // splits wall 2 (right wall)
        XCTAssertEqual(Set(room.uncertainWalls), [4])
        room.uncertainWalls = [1]
        room.moveCorner(1, to: Point2D(x: 210, y: 0))     // moving a corner checks its two walls
        XCTAssertTrue(room.uncertainWalls.isEmpty)
    }

    // MARK: RoomPlan (LiDAR) conversion

    func testRoomPlanWallsBecomeOutline() throws {
        // A 4 m × 3 m room centered on 0,0, walls as RoomPlan reports them.
        let walls = [
            WallSegment(centerX: 0, centerZ: -1.5, length: 4, angle: 0),
            WallSegment(centerX: 2, centerZ: 0, length: 3, angle: .pi / 2),
            WallSegment(centerX: 0, centerZ: 1.5, length: 4, angle: .pi),
            WallSegment(centerX: -2, centerZ: 0, length: 3, angle: -.pi / 2),
        ]
        let door = OpeningSegment(kind: .door, centerX: 1, centerZ: 1.5, width: 0.9)
        let draft = try XCTUnwrap(RoomPlanConverter.draft(walls: walls, openings: [door]))
        XCTAssertEqual(draft.corners.count, 4)
        XCTAssertEqual(PolygonGeometry.area(draft.corners), 120_000, accuracy: 1)
        XCTAssertTrue(draft.uncertainWalls.isEmpty)
        XCTAssertEqual(draft.features.first?.widthCm ?? 0, 90, accuracy: 0.001)
        XCTAssertTrue(PolygonGeometry.isClockwise(draft.corners))
    }

    func testTooFewWallsIsNoDraft() {
        XCTAssertNil(RoomPlanConverter.draft(walls: [WallSegment(centerX: 0, centerZ: 0, length: 3, angle: 0)], openings: []))
    }
}
