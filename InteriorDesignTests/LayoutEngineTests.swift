import XCTest
@testable import InteriorDesign

final class LayoutEngineTests: XCTestCase {
    // MARK: Test rooms and furniture

    private func item(_ type: ItemType, _ name: String, _ w: Double, _ d: Double, _ h: Double, fixed: Bool = false) -> LayoutItem {
        LayoutItem(id: UUID(), type: type, name: name, width: w, depth: d, height: h, isFixed: fixed)
    }

    /// The sample living room: 420 × 360, window on top, door bottom right.
    private var livingRoom: LayoutRoom {
        LayoutRoom(
            corners: PlanGeometry.rectangleCorners(width: 420, length: 360),
            features: [
                FixedFeature(kind: .door, wall: 2, offsetCm: 80, widthCm: 90),
                FixedFeature(kind: .window, wall: 0, offsetCm: 210, widthCm: 150),
                FixedFeature(kind: .outlet, wall: 3, offsetCm: 120, widthCm: 10),
                FixedFeature(kind: .outlet, wall: 1, offsetCm: 250, widthCm: 10),
            ]
        )
    }

    private var livingItems: [LayoutItem] {
        [
            item(.sofa, "Sofa", 210, 90, 85),
            item(.table, "Coffee table", 110, 60, 42),
            item(.tvStand, "TV stand", 150, 40, 50),
            item(.chair, "Armchair", 80, 85, 90),
            item(.shelf, "Bookshelf", 80, 30, 180),
            item(.lamp, "Floor lamp", 30, 30, 160),
        ]
    }

    /// Every suggestion must pass every hard rule.
    private func assertValid(_ layouts: [LayoutSuggestion], room: LayoutRoom, items: [LayoutItem], file: StaticString = #filePath, line: UInt = #line) {
        let rules = LayoutRules(room: room)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for layout in layouts {
            let placed = layout.placements.map { PlacedItem(item: byID[$0.itemID]!, placement: $0) }
            let problems = rules.problems(in: placed)
            XCTAssertTrue(problems.isEmpty, "\(layout.label): \(problems)", file: file, line: line)
            // Every item is either placed or listed as left out, never both.
            let ids = Set(layout.placements.map(\.itemID))
            XCTAssertEqual(ids.count + layout.leftOut.count, items.count, file: file, line: line)
            XCTAssertTrue(ids.isDisjoint(with: layout.leftOut), file: file, line: line)
        }
    }

    // MARK: 1. Living room

    func testLivingRoomFitsEverything() {
        let items = livingItems
        let layouts = LayoutEngine.suggest(room: livingRoom, items: items)
        XCTAssertGreaterThanOrEqual(layouts.count, 3)
        XCTAssertTrue(layouts[0].leftOut.isEmpty, "best layout fits everything")
        assertValid(layouts, room: livingRoom, items: items)
    }

    func testLivingRoomSeatingFacesFocalPoint() throws {
        let items = livingItems
        let best = try XCTUnwrap(LayoutEngine.suggest(room: livingRoom, items: items).first)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let placed = best.placements.map { PlacedItem(item: byID[$0.itemID]!, placement: $0) }
        let sofa = try XCTUnwrap(placed.first { $0.item.type == .sofa })
        let tv = try XCTUnwrap(placed.first { $0.item.type == .tvStand })
        XCTAssertGreaterThan(LayoutEngine.facing(sofa, toward: tv.center), 0.6)
    }

    func testLayoutsAreMeaningfullyDifferent() {
        let layouts = LayoutEngine.suggest(room: livingRoom, items: livingItems)
        for i in layouts.indices {
            for j in layouts.indices where j > i {
                XCTAssertGreaterThanOrEqual(LayoutEngine.difference(layouts[i], layouts[j]), 40)
            }
        }
        // And each has its own label.
        XCTAssertEqual(Set(layouts.map(\.label)).count, layouts.count)
    }

    func testCompleteLayoutsComeBeforePartialOnes() {
        let layouts = LayoutEngine.suggest(room: livingRoom, items: livingItems)
        // Once a layout leaves something out, no complete one follows it.
        let firstPartial = layouts.firstIndex { !$0.leftOut.isEmpty } ?? layouts.count
        XCTAssertTrue(layouts[firstPartial...].allSatisfy { !$0.leftOut.isEmpty })
    }

    // MARK: 2. Bedroom with a desk

    func testBedroom() throws {
        let room = LayoutRoom(
            corners: PlanGeometry.rectangleCorners(width: 350, length: 400),
            features: [
                FixedFeature(kind: .door, wall: 3, offsetCm: 330, widthCm: 80),
                FixedFeature(kind: .window, wall: 1, offsetCm: 200, widthCm: 120),
                FixedFeature(kind: .outlet, wall: 0, offsetCm: 60, widthCm: 10),
            ]
        )
        let items = [
            item(.bed, "Bed", 160, 200, 50),
            item(.dresser, "Dresser", 100, 45, 85),
            item(.desk, "Desk", 120, 60, 75),
            item(.chair, "Desk chair", 50, 50, 90),
            item(.lamp, "Lamp", 30, 30, 140),
        ]
        let layouts = LayoutEngine.suggest(room: room, items: items)
        XCTAssertFalse(layouts.isEmpty)
        XCTAssertTrue(layouts[0].leftOut.isEmpty)
        assertValid(layouts, room: room, items: items)
    }

    // MARK: 3. L-shaped room

    func testLShapedRoomKeepsItemsOutOfTheCutOut() {
        // 500 × 450 with the bottom-right 220 × 200 missing.
        let room = LayoutRoom(
            corners: [
                Point2D(x: 0, y: 0), Point2D(x: 500, y: 0), Point2D(x: 500, y: 250),
                Point2D(x: 280, y: 250), Point2D(x: 280, y: 450), Point2D(x: 0, y: 450),
            ],
            features: [
                FixedFeature(kind: .door, wall: 4, offsetCm: 100, widthCm: 90),
                FixedFeature(kind: .window, wall: 0, offsetCm: 250, widthCm: 160),
            ]
        )
        let items = [
            item(.sofa, "Sofa", 200, 90, 85),
            item(.chair, "Armchair", 80, 80, 90),
            item(.table, "Dining table", 140, 80, 75),
            item(.chair, "Dining chair", 45, 50, 90),
            item(.shelf, "Shelf", 80, 30, 180),
        ]
        let layouts = LayoutEngine.suggest(room: room, items: items)
        XCTAssertFalse(layouts.isEmpty)
        XCTAssertTrue(layouts[0].leftOut.isEmpty)
        assertValid(layouts, room: room, items: items)

        // Nothing in the missing corner.
        let cutOut = Box(minX: 280, minY: 250, maxX: 500, maxY: 450)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for p in layouts.flatMap(\.placements) {
            XCTAssertFalse(PlacedItem(item: byID[p.itemID]!, placement: p).footprint.overlaps(cutOut))
        }
    }

    // MARK: 4. Tiny room

    func testTinyRoom() {
        let room = LayoutRoom(
            corners: PlanGeometry.rectangleCorners(width: 220, length: 240),
            features: [FixedFeature(kind: .door, wall: 2, offsetCm: 60, widthCm: 75)]
        )
        let items = [
            item(.desk, "Small desk", 100, 50, 75),
            item(.chair, "Chair", 45, 45, 85),
            item(.lamp, "Lamp", 25, 25, 50),
        ]
        let layouts = LayoutEngine.suggest(room: room, items: items)
        XCTAssertFalse(layouts.isEmpty)
        XCTAssertTrue(layouts[0].leftOut.isEmpty)
        assertValid(layouts, room: room, items: items)
    }

    // MARK: 5. Too small for everything

    func testTooSmallReturnsBestPartialLayout() throws {
        let room = LayoutRoom(
            corners: PlanGeometry.rectangleCorners(width: 260, length: 280),
            features: [FixedFeature(kind: .door, wall: 2, offsetCm: 60, widthCm: 80)]
        )
        let items = [
            item(.bed, "Bed", 160, 200, 50),
            item(.sofa, "Sofa", 210, 90, 85),
            item(.dresser, "Dresser", 120, 50, 85),
            item(.desk, "Desk", 140, 70, 75),
        ]
        let layouts = LayoutEngine.suggest(room: room, items: items)
        let best = try XCTUnwrap(layouts.first)
        XCTAssertFalse(best.leftOut.isEmpty, "not everything fits")
        XCTAssertFalse(best.placements.isEmpty, "but something does")
        assertValid(layouts, room: room, items: items)
    }

    func testNothingFitsGivesEmptyPlacements() throws {
        let room = LayoutRoom(corners: PlanGeometry.rectangleCorners(width: 120, length: 120))
        let items = [item(.bed, "Bed", 160, 200, 50)]
        let best = try XCTUnwrap(LayoutEngine.suggest(room: room, items: items).first)
        XCTAssertTrue(best.placements.isEmpty)
        XCTAssertEqual(best.leftOut, items.map(\.id))
    }

    // MARK: Rules

    func testDoorSwingStaysClear() {
        let rules = LayoutRules(room: livingRoom)
        // A shelf right in front of the door. The bottom wall runs right to
        // left, so "80 cm along it" is x = 420 − 80 = 340.
        let shelf = item(.shelf, "Shelf", 80, 30, 180)
        let blocking = PlacedItem(item: shelf, placement: ItemPlacement(itemID: shelf.id, x: 340, y: 340, rotation: 180))
        XCTAssertTrue(rules.quickProblems(blocking, among: []).contains(.blocksDoor(shelf.id)))
    }

    // MARK: Doors (hard rules)

    func testSampleLivingRoomDoorZones() throws {
        // The door is on the bottom wall, which runs right to left, 80 cm
        // from the right corner: the opening spans x 295–385, hinge at 385.
        let door = try XCTUnwrap(LayoutRules(room: livingRoom).doors.first)
        XCTAssertEqual(door.swing, Box(minX: 295, minY: 270, maxX: 385, maxY: 360))
        // Past the hinge, into the corner where the open door folds back.
        XCTAssertEqual(door.behind, Box(minX: 385, minY: 270, maxX: 475, maxY: 360))
        XCTAssertEqual(door.approach, Box(minX: 280, minY: 270, maxX: 400, maxY: 360))
        XCTAssertEqual(door.tallBuffer, Box(minX: 250, minY: 240, maxX: 430, maxY: 360))
    }

    func testBehindDoorFollowsTheHinge() throws {
        var room = livingRoom
        room.features[0].hingeAtStart = false
        let door = try XCTUnwrap(LayoutRules(room: room).doors.first)
        let behind = try XCTUnwrap(door.behind)
        XCTAssertEqual(behind.minX, 205, accuracy: 0.001)
        XCTAssertEqual(behind.maxX, 295, accuracy: 0.001)
        XCTAssertEqual(behind.minY, 270, accuracy: 0.001)
        XCTAssertEqual(behind.maxY, 360, accuracy: 0.001)
    }

    func testOutwardDoorHasNoSwingButKeepsItsApproach() throws {
        var room = livingRoom
        room.features[0].opensInward = false
        let door = try XCTUnwrap(LayoutRules(room: room).doors.first)
        XCTAssertNil(door.swing)
        XCTAssertNil(door.behind)
        XCTAssertEqual(door.approach.height, 90)
    }

    func testShelfInTheCornerBehindTheDoorIsRejected() {
        // The spot from the bug report: the bookshelf against the right
        // wall in the bottom corner, where the door folds back.
        let rules = LayoutRules(room: livingRoom)
        let shelf = item(.shelf, "Bookshelf", 80, 30, 180)
        let corner = PlacedItem(item: shelf, placement: ItemPlacement(itemID: shelf.id, x: 404, y: 310, rotation: 90))
        XCTAssertTrue(rules.quickProblems(corner, among: []).contains(.blocksDoor(shelf.id)))
    }

    func testTallLampKeepsBackFromTheDoorway() {
        let rules = LayoutRules(room: livingRoom)
        let lamp = item(.lamp, "Floor lamp", 30, 30, 160)
        // Just left of the approach zone: fine for a low stool, not a lamp.
        let beside = PlacedItem(item: lamp, placement: ItemPlacement(itemID: lamp.id, x: 262, y: 340, rotation: 0))
        XCTAssertTrue(rules.quickProblems(beside, among: []).contains(.blocksDoor(lamp.id)))
        let stool = item(.other, "Stool", 30, 30, 45)
        let low = PlacedItem(item: stool, placement: ItemPlacement(itemID: stool.id, x: 262, y: 340, rotation: 0))
        XCTAssertFalse(rules.quickProblems(low, among: []).contains(.blocksDoor(stool.id)))
    }

    func testEveryDoorNeedsAPath() {
        // Two doors at opposite ends of a corridor-like room; a sofa across
        // the middle leaves each half reachable from only one door.
        let room = LayoutRoom(
            corners: PlanGeometry.rectangleCorners(width: 200, length: 500),
            features: [
                FixedFeature(kind: .door, wall: 0, offsetCm: 100, widthCm: 80),
                FixedFeature(kind: .door, wall: 2, offsetCm: 100, widthCm: 80),
            ]
        )
        let rules = LayoutRules(room: room)
        let sofa = item(.sofa, "Sofa", 200, 90, 85)
        let placed = [PlacedItem(item: sofa, placement: ItemPlacement(itemID: sofa.id, x: 100, y: 250, rotation: 0))]
        XCTAssertTrue(rules.unreachableItems(in: placed).contains(sofa.id))
    }

    /// Rooms with doors in awkward places: near corners, both hinge
    /// directions, two doors, and an L shape.
    private var doorTestRooms: [(String, LayoutRoom, [LayoutItem])] {
        var hingeFlipped = livingRoom
        hingeFlipped.features[0].hingeAtStart = false
        let twoDoors = LayoutRoom(
            corners: PlanGeometry.rectangleCorners(width: 450, length: 380),
            features: [
                FixedFeature(kind: .door, wall: 3, offsetCm: 60, widthCm: 85),
                FixedFeature(kind: .door, wall: 1, offsetCm: 300, widthCm: 80, hingeAtStart: false),
                FixedFeature(kind: .window, wall: 0, offsetCm: 225, widthCm: 140),
                FixedFeature(kind: .outlet, wall: 2, offsetCm: 200, widthCm: 10),
            ]
        )
        let lShape = LayoutRoom(
            corners: [
                Point2D(x: 0, y: 0), Point2D(x: 500, y: 0), Point2D(x: 500, y: 250),
                Point2D(x: 280, y: 250), Point2D(x: 280, y: 450), Point2D(x: 0, y: 450),
            ],
            features: [
                FixedFeature(kind: .door, wall: 4, offsetCm: 60, widthCm: 90),
                FixedFeature(kind: .window, wall: 0, offsetCm: 250, widthCm: 160),
            ]
        )
        return [
            ("living", livingRoom, livingItems),
            ("hinge flipped", hingeFlipped, livingItems),
            ("two doors", twoDoors, livingItems),
            ("L shape", lShape, livingItems),
            ("no TV", livingRoom, livingItems.filter { $0.type != .tvStand }),
        ]
    }

    /// Fails if any placed piece is in a door's swing, behind it, in its
    /// approach, or (for tall pieces) too close to the doorway.
    private func assertDoorsClear(_ layouts: [LayoutSuggestion], room: LayoutRoom, items: [LayoutItem], context: String, file: StaticString = #filePath, line: UInt = #line) {
        let rules = LayoutRules(room: room)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for layout in layouts {
            for p in layout.placements {
                let piece = PlacedItem(item: byID[p.itemID]!, placement: p)
                guard !piece.item.liesFlat else { continue }
                for door in rules.doors {
                    for zone in door.keepClear {
                        XCTAssertFalse(zone.overlaps(piece.footprint), "\(context) \(layout.label): \(piece.item.name) in door zone \(zone)", file: file, line: line)
                    }
                    if piece.item.isStanding {
                        XCTAssertFalse(door.tallBuffer.overlaps(piece.footprint), "\(context) \(layout.label): \(piece.item.name) too close to the doorway", file: file, line: line)
                    }
                }
            }
        }
    }

    func testNoOptionUsesDoorSpace() {
        for (name, room, items) in doorTestRooms {
            for seed: UInt64 in [1, 7, 42, 99, 2026] {
                var options = LayoutEngine.Options()
                options.seed = seed
                let layouts = LayoutEngine.suggest(room: room, items: items, options: options)
                XCTAssertFalse(layouts.isEmpty, name)
                assertDoorsClear(layouts, room: room, items: items, context: "\(name) seed \(seed)")
                assertValid(layouts, room: room, items: items)
            }
        }
    }

    func testDoorRulesHoldAcrossManySeeds() {
        // Fewer candidates per run so many seeds stay quick.
        for (name, room, items) in doorTestRooms {
            for seed: UInt64 in 100..<120 {
                var options = LayoutEngine.Options()
                options.seed = seed
                options.candidates = 15
                let layouts = LayoutEngine.suggest(room: room, items: items, options: options)
                assertDoorsClear(layouts, room: room, items: items, context: "\(name) seed \(seed)")
            }
        }
    }

    // MARK: Grouping (soft rules)

    private func placed(_ layout: LayoutSuggestion, _ items: [LayoutItem]) -> [PlacedItem] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return layout.placements.map { PlacedItem(item: byID[$0.itemID]!, placement: $0) }
    }

    /// Every complete living-room layout across a few seeds, with and
    /// without the TV.
    private func livingLayouts() -> [(LayoutSuggestion, [PlacedItem])] {
        livingLayouts(livingItems) + livingLayouts(livingItems.filter { $0.type != .tvStand })
    }

    private func livingLayouts(_ items: [LayoutItem]) -> [(LayoutSuggestion, [PlacedItem])] {
        [1, 7, 42, 99].flatMap { (seed: UInt64) -> [(LayoutSuggestion, [PlacedItem])] in
            var options = LayoutEngine.Options()
            options.seed = seed
            return LayoutEngine.suggest(room: livingRoom, items: items, options: options)
                .filter { $0.leftOut.isEmpty }
                .map { ($0, placed($0, items)) }
        }
    }

    func testCoffeeTableSitsInFrontOfTheSofa() throws {
        for (layout, pieces) in livingLayouts() {
            let sofa = try XCTUnwrap(pieces.first { $0.item.type == .sofa })
            let table = try XCTUnwrap(pieces.first { $0.item.isCoffeeTable })
            // In front of the sofa, 45–50 cm away, within 15 cm of centered.
            let toTable = Point2D(x: table.center.x - sofa.center.x, y: table.center.y - sofa.center.y)
            let ahead = toTable.x * sofa.front.x + toTable.y * sofa.front.y
            let across = abs(toTable.x * sofa.front.y - toTable.y * sofa.front.x)
            let gap = ahead - sofa.item.depth / 2 - table.item.depth / 2
            XCTAssertTrue((44...51).contains(gap), "\(layout.label): gap \(gap)")
            XCTAssertLessThanOrEqual(across, 15.5, layout.label)
        }
    }

    func testFloorLampStandsBesideASeat() throws {
        for (layout, pieces) in livingLayouts() {
            let lamp = try XCTUnwrap(pieces.first { $0.item.type == .lamp })
            let seats = pieces.filter { $0.item.type.isSeating }
            let gap = seats.map { LayoutEngine.gap(between: lamp.footprint, and: $0.footprint) }.min() ?? .infinity
            XCTAssertLessThanOrEqual(gap, 15, "\(layout.label): lamp is \(gap) cm from the nearest seat")
        }
    }

    func testArmchairJoinsTheSofa() throws {
        for (layout, pieces) in livingLayouts() {
            let chair = try XCTUnwrap(pieces.first { $0.item.isLoungeChair })
            let table = try XCTUnwrap(pieces.first { $0.item.isCoffeeTable })
            // Items only turn in quarter turns, so a chair off the table's
            // corner can't face it head on; 0.45 is within about 60°.
            XCTAssertLessThan(chair.center.distance(to: table.center), 240, layout.label)
            XCTAssertGreaterThan(LayoutEngine.facing(chair, toward: table.center), 0.45, layout.label)
        }
    }

    func testBestLayoutHasATightGroup() throws {
        for items in [livingItems, livingItems.filter { $0.type != .tvStand }] {
            for seed: UInt64 in [1, 7, 42, 99] {
                var options = LayoutEngine.Options()
                options.seed = seed
                let best = try XCTUnwrap(LayoutEngine.suggest(room: livingRoom, items: items, options: options).first)
                XCTAssertGreaterThan(best.breakdown.grouping, 0.9, "seed \(seed): \(best.label)")
            }
        }
    }

    func testEveryOptionKeepsTheGroupTogether() {
        // Including "Most open floor": open floor never means scattered.
        for (layout, _) in livingLayouts() {
            XCTAssertGreaterThan(layout.breakdown.grouping, 0.6, "\(layout.label) grouping \(layout.breakdown.grouping)")
        }
    }

    func testGroupingScoresTheBugReportLowerThanAGroup() {
        // The reported layout: armchair alone across the room, lamp by the
        // door, coffee table off to the side.
        let sofa = item(.sofa, "Sofa", 210, 90, 85)
        let table = item(.table, "Coffee table", 110, 60, 42)
        let chair = item(.chair, "Armchair", 80, 85, 90)
        let lamp = item(.lamp, "Floor lamp", 30, 30, 160)
        func at(_ i: LayoutItem, _ x: Double, _ y: Double, _ r: Int) -> PlacedItem {
            PlacedItem(item: i, placement: ItemPlacement(itemID: i.id, x: x, y: y, rotation: r))
        }
        let scattered = [at(sofa, 160, 46, 0), at(table, 330, 200, 90), at(chair, 60, 300, 180), at(lamp, 270, 340, 0)]
        let grouped = [at(sofa, 160, 46, 0), at(table, 160, 166, 0), at(chair, 302, 176, 90), at(lamp, 37, 20, 0)]
        XCTAssertLessThan(LayoutEngine.grouping(scattered), 0.4)
        XCTAssertGreaterThan(LayoutEngine.grouping(grouped), 0.9)
    }

    func testTallItemCannotBlockWindow() {
        let rules = LayoutRules(room: livingRoom)
        let shelf = item(.shelf, "Shelf", 80, 30, 180)
        let underWindow = PlacedItem(item: shelf, placement: ItemPlacement(itemID: shelf.id, x: 210, y: 16, rotation: 0))
        XCTAssertTrue(rules.quickProblems(underWindow, among: []).contains(.blocksWindow(shelf.id)))
        // A low dresser under the window is fine.
        let dresser = item(.dresser, "Dresser", 80, 40, 80)
        let low = PlacedItem(item: dresser, placement: ItemPlacement(itemID: dresser.id, x: 210, y: 21, rotation: 0))
        XCTAssertFalse(rules.quickProblems(low, among: []).contains(.blocksWindow(dresser.id)))
    }

    func testWalledOffItemIsUnreachable() {
        // A 200 cm wide corridor-like room; a sofa across the whole width
        // cuts the desk off from the door.
        let room = LayoutRoom(
            corners: PlanGeometry.rectangleCorners(width: 200, length: 500),
            features: [FixedFeature(kind: .door, wall: 2, offsetCm: 100, widthCm: 80)]
        )
        let rules = LayoutRules(room: room)
        let sofa = item(.sofa, "Sofa", 200, 90, 85)
        let desk = item(.desk, "Desk", 120, 60, 75)
        let placed = [
            PlacedItem(item: sofa, placement: ItemPlacement(itemID: sofa.id, x: 100, y: 250, rotation: 0)),
            PlacedItem(item: desk, placement: ItemPlacement(itemID: desk.id, x: 100, y: 31, rotation: 0)),
        ]
        XCTAssertTrue(rules.unreachableItems(in: placed).contains(desk.id))
    }

    func testFixedItemNeverMoves() throws {
        var items = livingItems
        items[4].isFixed = true  // the bookshelf
        let spot = ItemPlacement(itemID: items[4].id, x: 30, y: 200, rotation: 270)
        items[4].current = spot
        for layout in LayoutEngine.suggest(room: livingRoom, items: items) {
            XCTAssertEqual(layout.placements.first { $0.itemID == items[4].id }, spot)
        }
    }

    func testCurrentLayoutIsOffered() throws {
        // Take the best suggestion as "where things are now"...
        var items = livingItems
        let first = try XCTUnwrap(LayoutEngine.suggest(room: livingRoom, items: items).first)
        for i in items.indices {
            items[i].current = first.placements.first { $0.itemID == items[i].id }
        }
        // ...then it comes back as an option with nothing to move.
        let again = LayoutEngine.suggest(room: livingRoom, items: items)
        XCTAssertTrue(again.contains { layout in
            items.allSatisfy { ItemChange.of($0, in: layout.placements) == .stays }
        })
    }

    // MARK: Repeatable and fast

    func testSameSeedSameResult() {
        let items = livingItems
        let a = LayoutEngine.suggest(room: livingRoom, items: items)
        let b = LayoutEngine.suggest(room: livingRoom, items: items)
        XCTAssertEqual(a.map(\.placements), b.map(\.placements))
        XCTAssertEqual(a.map(\.label), b.map(\.label))
    }

    func testDifferentSeedCanDiffer() {
        let items = livingItems
        var options = LayoutEngine.Options()
        options.seed = 7
        let a = LayoutEngine.suggest(room: livingRoom, items: items)
        let b = LayoutEngine.suggest(room: livingRoom, items: items, options: options)
        XCTAssertFalse(a.isEmpty || b.isEmpty)
    }

    func testFastEnough() {
        let items = livingItems
        let started = Date()
        _ = LayoutEngine.suggest(room: livingRoom, items: items)
        // Under 1 s on a phone in a release build; debug test builds are
        // several times slower, so allow some slack here.
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.0)
    }

    // MARK: Missing pieces

    func testMissingPieces() {
        let missing = MissingPieces.suggest(for: [item(.sofa, "Sofa", 210, 90, 85), item(.tvStand, "TV", 150, 40, 50)])
        XCTAssertEqual(missing.map(\.name), ["Coffee table", "Rug", "Floor lamp"])

        let bedroom = MissingPieces.suggest(for: [item(.bed, "Bed", 160, 200, 50), item(.desk, "Desk", 120, 60, 75)])
        XCTAssertEqual(Set(bedroom.map(\.name)), ["Dresser", "Bedside lamp", "Desk chair"])

        XCTAssertTrue(MissingPieces.suggest(for: livingItems).isEmpty == false)
        XCTAssertFalse(MissingPieces.suggest(for: livingItems).contains { $0.name == "Coffee table" })
    }

    // MARK: Plan labels

    /// 6 pt per character, so sizes are easy to reason about.
    private func label(_ name: String, _ type: String, _ w: CGFloat, _ h: CGFloat) -> PlanLabels.Label {
        PlanLabels.choose(name: name, typeName: type, width: w, height: h) { CGFloat($0.count) * 6 }
    }

    func testPlanLabelUsesFullNameWhenItFits() {
        XCTAssertEqual(label("Floor lamp", "Lamp", 80, 40), .text("Floor lamp", sideways: false))
    }

    func testPlanLabelFallsBackToTypeName() {
        XCTAssertEqual(label("Floor lamp", "Lamp", 40, 40), .text("Lamp", sideways: false))
    }

    func testPlanLabelGoesSidewaysInTallThinBoxes() {
        XCTAssertEqual(label("Bookshelf", "Shelf", 22, 90), .text("Bookshelf", sideways: true))
    }

    func testPlanLabelUsesBadgeWhenNothingFits() {
        XCTAssertEqual(label("Floor lamp", "Lamp", 20, 20), .badge)
        // Too short for a line of text, however wide.
        XCTAssertEqual(label("Rug", "Rug", 200, 12), .badge)
    }

    func testPlanBadgesNumberOnlyTheSmallPieces() {
        let sofa = PlacedItem(item: item(.sofa, "Sofa", 210, 90, 85), placement: ItemPlacement(itemID: UUID(), x: 200, y: 100, rotation: 0))
        let lamp = PlacedItem(item: item(.lamp, "Floor lamp", 30, 30, 160), placement: ItemPlacement(itemID: UUID(), x: 50, y: 50, rotation: 0))
        // At 0.5 pt per cm the lamp is a 15 pt box: too small for any name.
        XCTAssertEqual(PlanLabels.badged([sofa, lamp], scale: 0.5).map(\.item.name), ["Floor lamp"])
        XCTAssertTrue(PlanLabels.badged([sofa, lamp], scale: 3).isEmpty)
    }
}
