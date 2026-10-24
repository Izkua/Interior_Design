import XCTest
@testable import InteriorDesign

/// Adding and editing furniture by hand.
final class ItemTests: XCTestCase {
    // MARK: Defaults

    func testNewDraftStartsAtTypeDefaults() {
        let draft = ItemDraft(type: .bed)
        let size = ItemType.bed.defaultSize
        XCTAssertEqual(draft.name, "Bed")
        XCTAssertEqual(draft.widthCm, size.width)
        XCTAssertEqual(draft.depthCm, size.depth)
        XCTAssertEqual(draft.heightCm, size.height)
    }

    func testEveryTypeHasARealisticSize() {
        for type in ItemType.allCases {
            let size = type.defaultSize
            XCTAssertGreaterThan(size.width, 0, type.displayName)
            XCTAssertGreaterThan(size.depth, 0, type.displayName)
            XCTAssertGreaterThan(size.height, 0, type.displayName)
            XCTAssertLessThanOrEqual(max(size.width, size.depth, size.height), 300, type.displayName)
        }
    }

    func testChangingTypeUpdatesUntouchedSizeAndName() {
        var draft = ItemDraft(type: .sofa)
        draft.setType(.desk)
        XCTAssertEqual(draft.name, "Desk")
        XCTAssertEqual(draft.widthCm, ItemType.desk.defaultSize.width)
    }

    func testChangingTypeKeepsWhatWasTyped() {
        var draft = ItemDraft(type: .sofa)
        draft.widthCm = 230
        draft.name = "Grandma's couch"
        draft.setType(.other)
        XCTAssertEqual(draft.widthCm, 230)
        XCTAssertEqual(draft.name, "Grandma's couch")
    }

    // MARK: Saving

    func testManualItemsAreNotEstimated() {
        var draft = ItemDraft(type: .chair)
        draft.name = "  Desk chair  "
        draft.isFixed = true
        let item = draft.makeItem()
        XCTAssertFalse(item.isEstimated)
        XCTAssertTrue(item.isFixed)
        XCTAssertEqual(item.name, "Desk chair")
        XCTAssertEqual(item.source, .owned)
    }

    func testSavingAnEstimateConfirmsIt() {
        let item = Item(type: .lamp, isEstimated: true)
        var draft = ItemDraft(item: item)
        draft.heightCm = 155
        draft.apply(to: item)
        XCTAssertFalse(item.isEstimated)
        XCTAssertEqual(item.heightCm, 155)
    }

    func testBlankNameFallsBackToType() {
        var draft = ItemDraft(type: .rug)
        draft.name = "   "
        XCTAssertEqual(draft.makeItem().name, "Rug")
    }

    func testEditingRoundTrip() {
        let room = Room(name: "Den", width: 300, length: 300)
        let item = Item(type: .shelf, name: "Books", widthCm: 80, depthCm: 30, heightCm: 180, notes: "Oak")
        item.room = room
        let draft = ItemDraft(item: item)
        XCTAssertEqual(draft.name, "Books")
        XCTAssertEqual(draft.notes, "Oak")
        XCTAssertEqual(draft.rooms.map(\.uuid), [room.uuid])
    }

    // MARK: Furniture sizes

    func testBareFurnitureNumberIsInchesInImperial() {
        XCTAssertEqual(Length.parse("34", system: .imperial, scale: .furniture) ?? 0, 86.36, accuracy: 0.01)
    }

    func testBareFurnitureNumberIsCentimetersInMetric() {
        XCTAssertEqual(Length.parse("85", system: .metric, scale: .furniture) ?? 0, 85, accuracy: 0.01)
        XCTAssertEqual(Length.parse("1.5", system: .metric, scale: .furniture) ?? 0, 1.5, accuracy: 0.01)
    }

    func testFurnitureStillReadsUnits() {
        XCTAssertEqual(Length.parse("6' 2\"", system: .imperial, scale: .furniture) ?? 0, 187.96, accuracy: 0.01)
        XCTAssertEqual(Length.parse("1.8 m", system: .metric, scale: .furniture) ?? 0, 180, accuracy: 0.01)
        XCTAssertEqual(Length.parse("72 in", system: .metric, scale: .furniture) ?? 0, 182.88, accuracy: 0.01)
    }

    func testRoomParsingIsUnchanged() {
        // A bare number is still feet (or meters) for walls.
        XCTAssertEqual(Length.parse("12", system: .imperial) ?? 0, 365.76, accuracy: 0.01)
        XCTAssertEqual(Length.parse("3.8", system: .metric) ?? 0, 380, accuracy: 0.01)
    }

    func testFurnitureFormatRoundTrips() {
        for cm in [1.0, 45, 86.36, 210] {
            for system in UnitSystem.allCases {
                let text = Length.formatFurniture(cm, system: system)
                let back = Length.parse(text, system: system, scale: .furniture) ?? 0
                XCTAssertEqual(back, cm, accuracy: system == .imperial ? 1.3 : 0.5, "\(text)")
            }
        }
    }

    func testThinRugNeverShowsZero() {
        XCTAssertEqual(Length.formatFurniture(1, system: .metric), "1 cm")
        XCTAssertEqual(Length.formatFurniture(1, system: .imperial), "0.4″")
    }
}
