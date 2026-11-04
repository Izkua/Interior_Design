import XCTest
import SwiftData
@testable import InteriorDesign

/// The layout screen is rebuilt every time the screen behind it redraws.
/// Building it must stay cheap, or the preview freezes on slower phones.
@MainActor
final class PreviewScreenTests: XCTestCase {
    private func room() throws -> (Room, ModelContainer) {
        let container = try ModelContainer(
            for: Room.self, Item.self, RoomLayout.self, Preferences.self, Product.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let room = Room(name: "Living room", width: 420, length: 360)
        container.mainContext.insert(room)
        var draft = ItemDraft(type: .sofa, room: room)
        draft.widthCm = 200
        container.mainContext.insert(draft.makeItem())
        try container.mainContext.save()
        return (room, container)
    }

    func testBuildingTheScreenManyTimesIsFast() throws {
        let (room, container) = try room()
        _ = container
        let rug = LayoutItem(id: UUID(), type: .rug, name: "Rug", width: 69, depth: 117, height: 1)
        let spot = ItemPlacement(itemID: rug.id, x: 200, y: 180, rotation: 0)
        let started = Date()
        // About what a few seconds of redraws would do.
        for _ in 0..<500 {
            _ = LayoutDetailView(room: room, furniture: [], preview: (rug, spot))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
    }

    func testRuleCheckIsReusedUntilSomethingMoves() throws {
        let (room, container) = try room()
        _ = container
        let cache = DetailCache(room: room, extra: nil)
        let item = try XCTUnwrap(cache.items.first)
        var placements = [ItemPlacement(itemID: item.id, x: 150, y: 100, rotation: 0)]
        let placed = { placements.map { PlacedItem(item: item, placement: $0) } }
        let first = cache.problems(in: placed(), placements: placements)
        XCTAssertEqual(cache.problems(in: placed(), placements: placements), first)
        // Push the sofa through the wall: the check runs again and notices.
        placements[0].x = -50
        XCTAssertFalse(cache.problems(in: placed(), placements: placements).isEmpty)
    }
}
