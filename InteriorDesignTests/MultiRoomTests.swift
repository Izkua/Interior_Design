import XCTest
import SwiftData
@testable import InteriorDesign

/// Furniture that can go in more than one room.
@MainActor
final class MultiRoomTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("MultiRoom-\(UUID().uuidString).store")
        container = try makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Room.self, Item.self, RoomLayout.self, Preferences.self, Product.self,
            configurations: ModelConfiguration(url: storeURL)
        )
    }

    private func room(_ name: String) -> Room {
        let room = Room(name: name, width: 400, length: 400)
        context.insert(room)
        return room
    }

    private func item(_ type: ItemType) -> Item {
        let item = Item(type: type)
        context.insert(item)
        return item
    }

    func testItemInTwoRoomsShowsInBoth() throws {
        let living = room("Living room"), bedroom = room("Bedroom"), office = room("Office")
        let chair = item(.chair)
        chair.setRooms([living, bedroom], anyRoom: false)
        try context.save()

        XCTAssertTrue(chair.belongs(to: living))
        XCTAssertTrue(chair.belongs(to: bedroom))
        XCTAssertFalse(chair.belongs(to: office))
        XCTAssertEqual(chair.room?.uuid, living.uuid)           // the first is the main room
        XCTAssertEqual(chair.roomSummary, "2 rooms")
        XCTAssertTrue(living.allItems.contains { $0.uuid == chair.uuid })
        XCTAssertTrue(bedroom.allItems.contains { $0.uuid == chair.uuid })
        XCTAssertFalse(office.allItems.contains { $0.uuid == chair.uuid })
        // Layouts for the bedroom include it.
        XCTAssertTrue(bedroom.layoutItems.contains { $0.id == chair.uuid })
    }

    func testAnyRoomShowsEverywhere() throws {
        let living = room("Living room"), bedroom = room("Bedroom")
        let lamp = item(.lamp)
        lamp.setRooms([], anyRoom: true)
        try context.save()
        XCTAssertTrue(living.allItems.contains { $0.uuid == lamp.uuid })
        XCTAssertTrue(bedroom.allItems.contains { $0.uuid == lamp.uuid })
        XCTAssertEqual(lamp.roomSummary, "Any room")
        XCTAssertFalse(lamp.isUnassigned)
    }

    func testUnassignedBelongsNowhere() throws {
        let living = room("Living room")
        let rug = item(.rug)
        try context.save()
        XCTAssertTrue(rug.isUnassigned)
        XCTAssertNil(rug.roomSummary)
        XCTAssertFalse(living.allItems.contains { $0.uuid == rug.uuid })
    }

    func testNoDuplicatesWhenListedTwice() throws {
        let living = room("Living room")
        let sofa = item(.sofa)
        sofa.setRooms([living, living], anyRoom: false)
        try context.save()
        XCTAssertEqual(sofa.assignedRooms.count, 1)
        XCTAssertEqual(living.allItems.filter { $0.uuid == sofa.uuid }.count, 1)
    }

    func testDraftRoundTrip() throws {
        let living = room("Living room"), bedroom = room("Bedroom")
        var draft = ItemDraft(type: .desk, room: living)
        draft.rooms.append(bedroom)
        let desk = draft.makeItem()
        context.insert(desk)
        try context.save()
        XCTAssertEqual(desk.assignedRooms.map(\.name), ["Living room", "Bedroom"])
        XCTAssertEqual(ItemDraft(item: desk).rooms.map(\.uuid), [living.uuid, bedroom.uuid])
    }

    func testDeletingARoomKeepsTheItemInItsOtherRooms() throws {
        let living = room("Living room"), bedroom = room("Bedroom")
        let chair = item(.chair)
        chair.setRooms([living, bedroom], anyRoom: false)
        try context.save()
        context.delete(living)
        try context.save()
        XCTAssertEqual(chair.assignedRooms.map(\.name), ["Bedroom"])
    }

    /// An item saved the old way (one room, no extra rooms) keeps its room
    /// after the app restarts.
    func testOldStyleItemKeepsItsRoom() throws {
        do {
            let den = room("Den")
            let shelf = item(.shelf)
            shelf.room = den   // exactly how items were saved before
            try context.save()
        }
        container = try makeContainer()
        let items = try context.fetch(FetchDescriptor<Item>())
        let shelf = try XCTUnwrap(items.first)
        XCTAssertEqual(shelf.assignedRooms.map(\.name), ["Den"])
        XCTAssertFalse(shelf.anyRoom)
        let den = try XCTUnwrap(try context.fetch(FetchDescriptor<Room>()).first)
        XCTAssertTrue(den.allItems.contains { $0.uuid == shelf.uuid })
    }

    func testSavedInAnotherRoomsLayoutIsNoticed() throws {
        let living = room("Living room"), bedroom = room("Bedroom")
        let sofa = item(.sofa)
        sofa.setRooms([living, bedroom], anyRoom: false)
        try context.save()
        XCTAssertTrue(sofa.savedLayoutRooms(among: [living, bedroom], excluding: living).isEmpty)

        bedroom.choose([ItemPlacement(itemID: sofa.uuid, x: 100, y: 100, rotation: 0)], label: "Test", score: 1, context: context)
        XCTAssertEqual(sofa.savedLayoutRooms(among: [living, bedroom], excluding: living).map(\.name), ["Bedroom"])
        // Not reported for the room you're looking at.
        XCTAssertTrue(sofa.savedLayoutRooms(among: [living, bedroom], excluding: bedroom).isEmpty)
    }
}
