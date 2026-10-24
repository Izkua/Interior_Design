import XCTest
import SwiftData
@testable import InteriorDesign

/// Week 1 "done when": a room you enter survives closing and reopening
/// the app. Each container here stands in for one launch, both reading
/// the same store file on disk.
final class PersistenceTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceTests-\(UUID().uuidString).store")
    }

    override func tearDownWithError() throws {
        // SwiftData also writes -shm and -wal files next to the store.
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
    }

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(url: storeURL)
        return try ModelContainer(
            for: Room.self, Item.self, RoomLayout.self, Preferences.self, Product.self,
            configurations: config
        )
    }

    @MainActor
    func testRoomSurvivesRelaunch() throws {
        var doorID: UUID?
        do {
            let container = try makeContainer()
            let context = container.mainContext
            let room = Room(name: "Bedroom", width: 350, length: 420)
            doorID = room.addFeature(.door).id
            context.insert(room)
            try context.save()
        }

        let container = try makeContainer()
        let context = container.mainContext
        let rooms = try context.fetch(FetchDescriptor<Room>())
        XCTAssertEqual(rooms.count, 1)
        let room = try XCTUnwrap(rooms.first)
        XCTAssertEqual(room.name, "Bedroom")
        XCTAssertEqual(room.width, 350, accuracy: 0.001)
        XCTAssertEqual(room.length, 420, accuracy: 0.001)
        XCTAssertEqual(room.features.map(\.id), [doorID])
    }

    @MainActor
    func testEditsAndDeletesSurviveRelaunch() throws {
        do {
            let container = try makeContainer()
            let context = container.mainContext
            let kept = Room(name: "Office", width: 300, length: 300)
            let removed = Room(name: "Spare", width: 250, length: 250)
            context.insert(kept)
            context.insert(removed)
            try context.save()

            kept.rename("Studio")
            kept.resize(width: 320, length: 400)
            context.delete(removed)
            try context.save()
        }

        let container = try makeContainer()
        let context = container.mainContext
        let rooms = try context.fetch(FetchDescriptor<Room>())
        XCTAssertEqual(rooms.map(\.name), ["Studio"])
        XCTAssertEqual(rooms.first?.width ?? 0, 320, accuracy: 0.001)
        XCTAssertEqual(rooms.first?.length ?? 0, 400, accuracy: 0.001)
    }

    @MainActor
    func testCustomRoomSurvivesRelaunch() throws {
        do {
            let container = try makeContainer()
            let context = container.mainContext
            let room = Room(name: "L-shaped den", width: 400, length: 400)
            room.setShape(.custom)
            room.insertCorner(at: Point2D(x: 410, y: 200))
            room.moveCorner(3, to: Point2D(x: 200, y: 200))
            room.insertCorner(at: Point2D(x: 200, y: 410))
            room.setWallLength(0, to: 400)
            room.addFeature(.window)
            context.insert(room)
            try context.save()
        }

        let container = try makeContainer()
        let rooms = try container.mainContext.fetch(FetchDescriptor<Room>())
        let room = try XCTUnwrap(rooms.first)
        XCTAssertEqual(room.shape, .custom)
        XCTAssertEqual(room.corners.count, 6)
        XCTAssertEqual(PolygonGeometry.interiorAngle(at: 3, corners: room.corners), 270, accuracy: 0.5)
        XCTAssertEqual(room.measuredLength(0), 400)
        XCTAssertEqual(room.features.count, 1)
    }

    @MainActor
    func testItemWithRoomSurvivesRelaunch() throws {
        do {
            let container = try makeContainer()
            let context = container.mainContext
            let room = Room(name: "Office", width: 300, length: 300)
            context.insert(room)
            var draft = ItemDraft(type: .desk, room: room)
            draft.widthCm = 152
            draft.isFixed = true
            context.insert(draft.makeItem())
            try context.save()
        }

        let container = try makeContainer()
        let items = try container.mainContext.fetch(FetchDescriptor<Item>())
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.widthCm, 152)
        XCTAssertTrue(item.isFixed)
        XCTAssertFalse(item.isEstimated)
        XCTAssertEqual(item.room?.name, "Office")
    }
}
