import XCTest
@testable import InteriorDesign

/// The Furniture page of a room: what's placed, what isn't, and what's in
/// trouble after the room changes.
final class RoomFurnitureTests: XCTestCase {
    private let square = LayoutRoom(corners: [Point2D(x: 0, y: 0), Point2D(x: 400, y: 0), Point2D(x: 400, y: 400), Point2D(x: 0, y: 400)])

    private func item(_ type: ItemType, at spot: ItemPlacement?) -> LayoutItem {
        let size = type.defaultSize
        let id = spot?.itemID ?? UUID()
        return LayoutItem(id: id, type: type, name: type.displayName, width: size.width, depth: size.depth, height: size.height, current: spot)
    }

    func testSplitsPlacedAndNotPlaced() {
        let id = UUID()
        let sofa = item(.sofa, at: ItemPlacement(itemID: id, x: 200, y: 340, rotation: 0))
        let lamp = item(.lamp, at: nil)
        XCTAssertEqual(RoomFurniture.placed([sofa, lamp]).map(\.item.id), [id])
        XCTAssertEqual(RoomFurniture.unplaced([sofa, lamp]).map(\.id), [lamp.id])
    }

    func testUnplacedPiecesStartInsideTheRoomReadyToDrag() {
        let lamp = item(.lamp, at: nil)
        let suggestion = RoomFurniture.currentSuggestion([lamp], room: square)
        let spot = try? XCTUnwrap(suggestion.placements.first { $0.itemID == lamp.id })
        XCTAssertEqual(spot?.x ?? 0, 200, accuracy: 0.1)
        XCTAssertEqual(spot?.y ?? 0, 200, accuracy: 0.1)
        XCTAssertTrue(suggestion.leftOut.isEmpty)
    }

    func testKeepsPositionsAndFlagsPiecesOutsideAfterTheRoomShrinks() {
        // A sofa against the far wall of a 4 m room; then the room is made 2.5 m deep.
        let id = UUID()
        let sofa = item(.sofa, at: ItemPlacement(itemID: id, x: 200, y: 350, rotation: 0))
        let placed = RoomFurniture.placed([sofa])

        let smaller = LayoutRoom(corners: [Point2D(x: 0, y: 0), Point2D(x: 400, y: 0), Point2D(x: 400, y: 250), Point2D(x: 0, y: 250)])
        // Its spot is kept as it was, and it's flagged instead of moved.
        XCTAssertEqual(placed.first?.placement.y, 350)
        XCTAssertTrue(RoomFurniture.problemIDs(placed, room: smaller).contains(id))
    }

    func testPlaceAllPutsEverythingSomewhere() {
        let items = [item(.sofa, at: nil), item(.lamp, at: nil)]
        let suggestion = RoomFurniture.placeAll(items, room: square)
        XCTAssertEqual(Set(suggestion.placements.map(\.itemID)), Set(items.map(\.id)))
    }
}
