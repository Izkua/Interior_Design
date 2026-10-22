import XCTest
@testable import InteriorDesign

final class RoomTests: XCTestCase {
    func testResizeKeepsFeaturesOnWall() {
        let room = Room(name: "Test", width: 400, length: 500)
        let door = room.addFeature(.door)
        room.resize(width: 200, length: 200)
        let moved = room.features.first { $0.id == door.id }
        XCTAssertNotNil(moved)
        let wallLength = PlanGeometry.wallLength(moved?.wall ?? 0, corners: room.corners)
        XCTAssertLessThanOrEqual(moved?.offsetCm ?? 999, wallLength)
    }

    func testSquareMakesSidesEqual() {
        let room = Room(name: "Test", width: 400, length: 500)
        room.setShape(.square)
        XCTAssertEqual(room.width, room.length, accuracy: 0.001)
    }

    func testRenameIgnoresBlank() {
        let room = Room(name: "Den", width: 300, length: 300)
        room.rename("   ")
        XCTAssertEqual(room.name, "Den")
    }

    func testAddAndRemoveFeature() {
        let room = Room(name: "Test", width: 400, length: 500)
        let window = room.addFeature(.window)
        XCTAssertEqual(room.features.count, 1)
        room.removeFeature(id: window.id)
        XCTAssertTrue(room.features.isEmpty)
    }

    func testNewFeaturesDoNotOverlap() {
        let room = Room(name: "Test", width: 400, length: 500)
        let first = room.addFeature(.door)
        let second = room.addFeature(.door)
        if first.wall == second.wall {
            let gap = abs(first.offsetCm - second.offsetCm)
            XCTAssertGreaterThanOrEqual(gap, (first.widthCm + second.widthCm) / 2 - 0.001)
        }
    }

    func testFeatureWidthNeverExceedsWall() {
        let room = Room(name: "Test", width: 400, length: 500)
        let window = room.addFeature(.window)
        room.updateFeature(id: window.id) { $0.widthCm = 900 }
        let updated = room.features.first { $0.id == window.id }!
        XCTAssertLessThanOrEqual(updated.widthCm, PlanGeometry.wallLength(updated.wall, corners: room.corners))
    }

    func testShrinkingRoomShrinksWideFeatures() {
        let room = Room(name: "Test", width: 400, length: 500)
        let window = room.addFeature(.window)
        room.updateFeature(id: window.id) { $0.widthCm = 350 }
        room.resize(width: 200, length: 200)
        let updated = room.features.first { $0.id == window.id }!
        XCTAssertLessThanOrEqual(updated.widthCm, 200)
    }

    func testOldSavedFeaturesStillLoad() throws {
        // Saved before doors had a hinge side or swing direction.
        let json = #"{"kind":"door","wall":2,"offsetCm":80,"widthCm":90}"#
        let feature = try JSONDecoder().decode(FixedFeature.self, from: Data(json.utf8))
        XCTAssertEqual(feature.kind, .door)
        XCTAssertTrue(feature.hingeAtStart)
        XCTAssertTrue(feature.opensInward)
    }
}
