import XCTest
@testable import InteriorDesign

final class ItemCategoryTests: XCTestCase {
    func testEveryTypeHasACategory() {
        XCTAssertEqual(ItemType.sofa.category, .furniture)
        XCTAssertEqual(ItemType.lamp.category, .furniture)
        XCTAssertEqual(ItemType.poster.category, .wallDecor)
        XCTAssertEqual(ItemType.mirror.category, .wallDecor)
        XCTAssertEqual(ItemType.plant.category, .smallDecor)
        XCTAssertEqual(ItemType.monitor.category, .smallDecor)
        // Every type shows up in exactly one category's list.
        let listed = ItemCategory.allCases.flatMap(\.types)
        XCTAssertEqual(listed.count, ItemType.allCases.count)
        XCTAssertEqual(Set(listed), Set(ItemType.allCases))
    }

    func testWallDecorTypesMapToHangingKinds() {
        for type in ItemCategory.wallDecor.types {
            let kind = try! XCTUnwrap(type.decorKind)
            XCTAssertEqual(kind.itemType, type)
        }
        XCTAssertNil(ItemType.sofa.decorKind)
    }

    func testDecorLabelsWinOverFurniture() {
        XCTAssertEqual(LabelMapper.label(from: [("table_lamp", 0.7)])?.type, .tableLamp)
        XCTAssertEqual(LabelMapper.label(from: [("floor_lamp", 0.7)])?.type, .lamp)
        XCTAssertEqual(LabelMapper.label(from: [("houseplant", 0.6)])?.type, .plant)
        XCTAssertEqual(LabelMapper.label(from: [("wall_clock", 0.6)])?.type, .wallClock)
        XCTAssertEqual(LabelMapper.label(from: [("coffee_table", 0.6)])?.type, .table)
    }

    func testProductTypesFromNames() {
        XCTAssertEqual(ProductNormalizer.itemType(nil, name: "Linen table lamp"), .tableLamp)
        XCTAssertEqual(ProductNormalizer.itemType(nil, name: "Oak floating shelf"), .wallShelf)
        XCTAssertEqual(ProductNormalizer.itemType(nil, name: "Round wall mirror"), .mirror)
        XCTAssertEqual(ProductNormalizer.itemType(nil, name: "Oak coffee table"), .table)
    }

    func testCategoryFilter() {
        let products = [
            CatalogProduct(id: "a", name: "Sofa", price: 500, type: .sofa, retailer: "S"),
            CatalogProduct(id: "b", name: "Poster", price: 20, type: .poster, retailer: "S"),
            CatalogProduct(id: "c", name: "Plant", price: 30, type: .plant, retailer: "S"),
            CatalogProduct(id: "d", name: "Mystery", price: 30, retailer: "S"),
        ]
        var query = CatalogQuery()
        query.category = .wallDecor
        let ids = CatalogRanking.filter(products, query: query, budget: ShoppingBudget()).map(\.id)
        // Unknown types stay, since the search words asked for this kind.
        XCTAssertEqual(ids, ["b", "d"])
    }
}

final class RoomVibeTests: XCTestCase {
    let oak = RGB(r: 0.6, g: 0.42, b: 0.25)
    let cream = RGB(r: 0.93, g: 0.9, b: 0.82)
    let navy = RGB(r: 0.15, g: 0.2, b: 0.4)
    let grey = RGB(r: 0.5, g: 0.5, b: 0.5)

    func testColorNamesAndTones() {
        XCTAssertEqual(oak.colorName, "Brown")
        XCTAssertEqual(oak.tone, .warm)
        XCTAssertEqual(navy.colorName, "Blue")
        XCTAssertEqual(navy.tone, .cool)
        XCTAssertEqual(grey.colorName, "Grey")
        XCTAssertEqual(grey.tone, .neutral)
        XCTAssertEqual(RGB(r: 0.98, g: 0.98, b: 0.97).colorName, "White")
        XCTAssertEqual(RGB(hex: oak.hex)?.hex, oak.hex)
    }

    func testWarmRoom() throws {
        let vibe = try XCTUnwrap(RoomVibe.from([(oak, 3), (cream, 2), (grey, 1)]))
        XCTAssertEqual(vibe.tone, .warm)
        XCTAssertEqual(vibe.colorNames.first, "Brown")
        XCTAssertTrue(vibe.title.hasPrefix("Warm"))
        // A color already in the room beats a neutral, which beats a clash.
        XCTAssertGreaterThan(vibe.match(colors: ["Brown"]), vibe.match(colors: ["Black"]))
        XCTAssertGreaterThan(vibe.match(colors: ["Black"]), vibe.match(colors: ["Blue"]))
        XCTAssertEqual(vibe.match(colors: []), 0)
    }

    func testCoolRoomAndEmpty() throws {
        let vibe = try XCTUnwrap(RoomVibe.from([(navy, 3), (grey, 1)]))
        XCTAssertEqual(vibe.tone, .cool)
        XCTAssertNil(RoomVibe.from([]))
    }

    func testVibeLiftsMatchingProducts() {
        let vibe = RoomVibe.from([(oak, 3), (cream, 2)])
        let brown = CatalogProduct(id: "brown", name: "Brown vase", price: 30, colors: ["Brown"], retailer: "S")
        let blue = CatalogProduct(id: "blue", name: "Blue vase", price: 30, colors: ["Blue"], retailer: "S")
        let ranked = CatalogRanking.rank([blue, brown], preferences: ShoppingPreferences(vibe: vibe), budget: ShoppingBudget())
        XCTAssertEqual(ranked.first?.id, "brown")
    }
}

final class WallDecorPlannerTests: XCTestCase {
    let sofaID = UUID()
    let ceiling = 250.0

    /// A 400 cm wall with a sofa in the middle, and a bare 300 cm wall with a window.
    var walls: [PlannerWall] {
        let sofa = WallFurniture(id: sofaID, name: "Sofa", rect: WallRect(minX: 100, minY: 0, maxX: 300, maxY: 85))
        return [
            PlannerWall(index: 0, name: "Top wall", length: 400, blocked: [], furniture: [sofa], furnitureTypes: [sofaID: .sofa]),
            PlannerWall(index: 1, name: "Right wall", length: 300,
                        blocked: [WallRect(minX: 100, minY: 90, maxX: 200, maxY: 210)], furniture: []),
        ]
    }

    func pieces(_ n: Int, kind: DecorKind = .frame) -> [WallDecor] {
        (0..<n).map { _ in WallDecor(kind: kind, wall: 1, centerX: 150) }
    }

    func testGroupsArtOverTheSofa() throws {
        let art = pieces(3)
        let idea = try XCTUnwrap(WallDecorPlanner.aboveAnchor(walls: walls, pieces: art, ceiling: ceiling, colors: [:]))
        XCTAssertTrue(idea.label.contains("sofa"))
        XCTAssertEqual(idea.decor.count, 3)
        for d in idea.decor {
            XCTAssertEqual(d.wall, 0)
            // Above the sofa with a gap, and inside its width.
            XCTAssertGreaterThanOrEqual(d.rect.minY, 85 + WallDecorGeometry.gapAboveFurnitureCm - 0.5)
            XCTAssertGreaterThanOrEqual(d.rect.minX, 100 - 0.5)
            XCTAssertLessThanOrEqual(d.rect.maxX, 300 + 0.5)
        }
        // No two pieces overlap.
        for (i, a) in idea.decor.enumerated() {
            for b in idea.decor.dropFirst(i + 1) { XCTAssertFalse(a.rect.overlaps(b.rect)) }
        }
    }

    func testTooWideForOneRowMakesAGrid() {
        let wide = (0..<4).map { _ in WallDecor(kind: .canvas, wall: 0, centerX: 0, widthCm: 80, heightCm: 60) }
        let rows = WallDecorPlanner.gridRows(wide, maxWidth: 180, gap: 8)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.count), [2, 2])
    }

    func testBoldestPieceInTheMiddle() {
        let a = WallDecor(kind: .frame, wall: 0, centerX: 0, itemID: UUID())
        let b = WallDecor(kind: .frame, wall: 0, centerX: 0, itemID: UUID())
        let c = WallDecor(kind: .frame, wall: 0, centerX: 0, itemID: UUID())
        let colors = [b.itemID!: RGB(r: 0.9, g: 0.1, b: 0.1), a.itemID!: RGB(r: 0.5, g: 0.5, b: 0.5), c.itemID!: RGB(r: 0.5, g: 0.5, b: 0.5)]
        let order = WallDecorPlanner.centerOut([a, b, c], colors: colors)
        XCTAssertEqual(order[1].id, b.id)
    }

    func testNothingCoversTheWindow() {
        let ideas = WallDecorPlanner.suggest(walls: walls, pieces: pieces(4), ceiling: ceiling)
        XCTAssertFalse(ideas.isEmpty)
        let window = walls[1].blocked[0]
        for idea in ideas {
            XCTAssertEqual(idea.decor.count, 4, idea.label)
            for d in idea.decor where d.wall == 1 {
                XCTAssertFalse(d.rect.overlaps(window), idea.label)
            }
        }
    }

    func testTVGoesOverTheStand() throws {
        let standID = UUID()
        let stand = WallFurniture(id: standID, name: "TV stand", rect: WallRect(minX: 50, minY: 0, maxX: 200, maxY: 50))
        var ws = walls
        ws[1].furniture = [stand]
        ws[1].furnitureTypes = [standID: .tvStand]
        ws[1].blocked = []
        let tv = WallDecor(kind: .tv, wall: 0, centerX: 60)
        let idea = try XCTUnwrap(WallDecorPlanner.aboveAnchor(walls: ws, pieces: [tv] + pieces(1), ceiling: ceiling, colors: [:]))
        let placedTV = try XCTUnwrap(idea.decor.first { $0.id == tv.id })
        XCTAssertEqual(placedTV.wall, 1)
        XCTAssertEqual(placedTV.centerX, 125, accuracy: 0.5)
    }

    func testWallFitCheck() {
        let space = DecorSpace(ceiling: ceiling)
        XCTAssertTrue(DecorFit.wall(width: 100, height: 70, walls: walls, space: space).fits)
        XCTAssertFalse(DecorFit.wall(width: 500, height: 70, walls: walls, space: space).fits)
        XCTAssertFalse(DecorFit.wall(width: 50, height: 240, walls: walls, space: space).fits)
    }
}

final class SmallDecorPlannerTests: XCTestCase {
    let desk = DecorSurface(id: UUID(), type: .desk, name: "Desk", width: 140, depth: 70, height: 75)
    let shelf = DecorSurface(id: UUID(), type: .shelf, name: "Bookcase", width: 80, depth: 30, height: 180)
    let coffee = DecorSurface(id: UUID(), type: .table, name: "Coffee table", width: 110, depth: 60, height: 45)

    func piece(_ type: ItemType, color: RGB? = nil) -> DecorPiece {
        let s = type.defaultSize
        return DecorPiece(id: UUID(), type: type, name: type.displayName, width: s.width, depth: s.depth, height: s.height, color: color)
    }

    func testMonitorAndLampOnTheDesk() throws {
        let monitor = piece(.monitor), lamp = piece(.tableLamp), books = piece(.books)
        let ideas = SmallDecorPlanner.suggest(pieces: [monitor, lamp, books], surfaces: [desk, shelf, coffee])
        let best = try XCTUnwrap(ideas.first)
        let spots = Dictionary(uniqueKeysWithValues: best.spots.map { ($0.itemID, $0) })
        XCTAssertEqual(spots[monitor.id]?.hostID, desk.id)
        XCTAssertEqual(spots[books.id]?.hostID, shelf.id)
        XCTAssertTrue(best.leftOut.isEmpty)
        // Monitors stay on the desk in every idea.
        for idea in ideas {
            XCTAssertEqual(idea.spots.first { $0.itemID == monitor.id }?.hostID, desk.id, idea.label)
        }
    }

    func testArrangementStaysOnTheSurfaceWithoutOverlap() {
        let pieces = [piece(.tableLamp), piece(.monitor), piece(.deskStorage)]
        let offsets = SmallDecorPlanner.arrange(pieces, on: desk)
        let spans = pieces.map { p -> (Double, Double) in
            let x = offsets[p.id]!
            return (x - p.width / 2, x + p.width / 2)
        }.sorted { $0.0 < $1.0 }
        XCTAssertGreaterThanOrEqual(spans.first!.0, 0)
        XCTAssertLessThanOrEqual(spans.last!.1, desk.width)
        for (a, b) in zip(spans, spans.dropFirst()) { XCTAssertLessThanOrEqual(a.1, b.0 + 0.01) }
        // The lamp is at the left end.
        XCTAssertLessThan(offsets[pieces[0].id]!, offsets[pieces[1].id]!)
    }

    func testTooManyPiecesAreLeftOut() {
        let tiny = DecorSurface(id: UUID(), type: .shelf, name: "Shelf", width: 40, depth: 30, height: 100)
        let plan = SmallDecorPlanner.suggest(pieces: [piece(.books), piece(.books), piece(.books)], surfaces: [tiny])
        XCTAssertEqual(plan.first?.leftOut.count, 2)
    }

    func testBigPlantStandsOnTheFloor() {
        var plant = piece(.plant)
        plant.height = 120
        let plan = SmallDecorPlanner.suggest(pieces: [plant], surfaces: [desk])
        XCTAssertEqual(plan.first?.spots.first?.hostID, nil)
    }

    func testColorGroupsKeepFamiliesTogether() throws {
        let warm = RGB(r: 0.7, g: 0.4, b: 0.2), cool = RGB(r: 0.2, g: 0.4, b: 0.6)
        let pieces = [piece(.vase, color: warm), piece(.candle, color: warm), piece(.plant, color: cool), piece(.tableClock, color: cool)]
        let groups = SmallDecorPlanner.colorGroups(pieces, [coffee, shelf, desk])
        XCTAssertTrue(groups.leftOut.isEmpty)
        let host = Dictionary(uniqueKeysWithValues: groups.spots.map { ($0.itemID, $0.hostID) })
        XCTAssertEqual(host[pieces[0].id], host[pieces[1].id])
        XCTAssertEqual(host[pieces[2].id], host[pieces[3].id])
        XCTAssertNotEqual(host[pieces[0].id], host[pieces[2].id])
    }

    func testSurfaceFitCheck() {
        var space = DecorSpace(surfaces: [desk])
        XCTAssertTrue(DecorFit.surface(type: .tableLamp, width: 25, depth: 25, height: 50, space: space).fits)
        // Books don't go on a desk that's already full.
        space.usedWidth[desk.id] = 120
        XCTAssertFalse(DecorFit.surface(type: .books, width: 25, depth: 18, height: 22, space: space).fits)
        XCTAssertFalse(DecorFit.surface(type: .vase, width: 15, depth: 15, height: 30, space: DecorSpace()).fits)
    }

    func testMissingDecor() {
        let sofa = LayoutItem(id: UUID(), type: .sofa, name: "Sofa", width: 200, depth: 90, height: 85)
        let desk = LayoutItem(id: UUID(), type: .desk, name: "Desk", width: 140, depth: 70, height: 75)
        let names = MissingPieces.suggest(for: [sofa, desk], decor: []).map(\.name)
        XCTAssertTrue(names.contains("Wall art"))
        XCTAssertTrue(names.contains("Desk lamp"))
        XCTAssertTrue(names.contains("Plant"))
        let none = MissingPieces.suggest(for: [sofa, desk], decor: [.poster, .tableLamp, .plant]).map(\.name)
        XCTAssertFalse(none.contains("Wall art"))
        // Without decor info, only furniture is suggested.
        XCTAssertFalse(MissingPieces.suggest(for: [sofa]).contains { $0.type.category != .furniture })
    }
}

final class DecorRoundTwoTests: XCTestCase {
    func testDecorSearchesSendDecorWords() {
        var q = CatalogQuery()
        q.category = .wallDecor
        XCTAssertEqual(BackendCatalogService.wireQuery(q).text, "wall art decor")
        q.type = .tableLamp
        XCTAssertEqual(BackendCatalogService.wireQuery(q).text, "table lamp")
        q.text = "brass"
        XCTAssertEqual(BackendCatalogService.wireQuery(q).text, "brass")
        var furniture = CatalogQuery()
        furniture.category = .furniture
        XCTAssertEqual(BackendCatalogService.wireQuery(furniture).text, "")
    }

    func testServerTypesAreFixedForDecor() {
        let lamp = CatalogProduct(id: "1", name: "Linen Table Lamp", price: 40, type: .lamp, retailer: "S")
        XCTAssertEqual(BackendCatalogService.retyped(lamp).type, .tableLamp)
        let bench = CatalogProduct(id: "2", name: "Oak dining bench", price: 90, retailer: "S")
        XCTAssertNil(BackendCatalogService.retyped(bench).type)
    }

    func testPosterPalette() {
        let red = RGB(r: 0.8, g: 0.1, b: 0.1), blue = RGB(r: 0.1, g: 0.2, b: 0.8)
        let pixels = Array(repeating: red, count: 1500) + Array(repeating: blue, count: 804)
        let palette = PhotoColors.palette(fromPixels: pixels, count: 3)
        XCTAssertEqual(palette.count, 2)
        XCTAssertEqual(palette.first?.colorName, "Brown")  // a deep red reads as warm brown-red
        XCTAssertEqual(palette.last?.colorName, "Blue")
    }

    func testSurfacePlacementRoundTrip() {
        let desk = LayoutItem(id: UUID(), type: .desk, name: "Desk", width: 140, depth: 70, height: 75)
        for rotation in [0, 90, 180, 270] {
            let host = PlacedItem(item: desk, placement: ItemPlacement(itemID: desk.id, x: 200, y: 150, rotation: rotation))
            let p = SurfacePlacement.point(offset: 30, on: host)
            XCTAssertEqual(SurfacePlacement.offset(of: p, on: host, pieceWidth: 20), 30, accuracy: 0.01)
        }
        // Kept on the desk.
        let host = PlacedItem(item: desk, placement: ItemPlacement(itemID: desk.id, x: 200, y: 150, rotation: 0))
        XCTAssertEqual(SurfacePlacement.offset(of: Point2D(x: 900, y: 150), on: host, pieceWidth: 20), 130, accuracy: 0.01)
    }

    func testSkipDepth() {
        var steps = MeasureSteps()
        steps.setStart(); steps.setEnd(distanceCm: 45)   // height
        steps.setStart(); steps.setEnd(distanceCm: 62)   // width
        XCTAssertEqual(steps.current, .depth)
        steps.skip(using: 20)
        XCTAssertTrue(steps.isDone)
        XCTAssertEqual(steps.value(.depth), 20)
    }

    func testOldDecorStillLoads() throws {
        let json = #"{"kind":"poster","wall":1,"centerX":100}"#.data(using: .utf8)!
        let piece = try JSONDecoder().decode(WallDecor.self, from: json)
        XCTAssertEqual(piece.colors, [])
        XCTAssertNil(piece.mainColor)
    }
}

final class MoreIdeasTests: XCTestCase {
    func testMoreWallIdeasHaveUniqueNames() {
        let sofaID = UUID(), deskID = UUID()
        let walls = [
            PlannerWall(index: 0, name: "Top wall", length: 400, blocked: [],
                        furniture: [WallFurniture(id: sofaID, name: "Sofa", rect: WallRect(minX: 100, minY: 0, maxX: 300, maxY: 85))],
                        furnitureTypes: [sofaID: .sofa]),
            PlannerWall(index: 1, name: "Right wall", length: 350, blocked: [],
                        furniture: [WallFurniture(id: deskID, name: "Desk", rect: WallRect(minX: 50, minY: 0, maxX: 190, maxY: 75))],
                        furnitureTypes: [deskID: .desk]),
            PlannerWall(index: 2, name: "Bottom wall", length: 400, blocked: [], furniture: []),
        ]
        let pieces = (0..<3).map { _ in WallDecor(kind: .frame, wall: 0, centerX: 0) }
        let ideas = WallDecorPlanner.suggest(walls: walls, pieces: pieces, ceiling: 250)
        XCTAssertGreaterThan(ideas.count, 3)
        XCTAssertEqual(Set(ideas.map(\.label)).count, ideas.count)
    }

    func testIdeaWindowWraps() {
        XCTAssertEqual(IdeaPage.window([1, 2, 3, 4, 5], start: 3), [4, 5, 1])
        XCTAssertEqual(IdeaPage.window([1, 2], start: 0), [1, 2])
    }
}

final class SmallDecorVarietyTests: XCTestCase {
    func testMonitorWithNoDeskStillGetsSeveralIdeas() {
        let coffee = DecorSurface(id: UUID(), type: .table, name: "Coffee table", width: 110, depth: 60, height: 45)
        let stand = DecorSurface(id: UUID(), type: .tvStand, name: "TV stand", width: 150, depth: 40, height: 50)
        let shelf = DecorSurface(id: UUID(), type: .shelf, name: "Bookshelf", width: 80, depth: 30, height: 180)
        let s = ItemType.monitor.defaultSize
        let monitor = DecorPiece(id: UUID(), type: .monitor, name: "Monitor", width: s.width, depth: s.depth, height: s.height)
        let plant = DecorPiece(id: UUID(), type: .plant, name: "Plant", width: 25, depth: 25, height: 40)
        let ideas = SmallDecorPlanner.suggest(pieces: [monitor, plant], surfaces: [coffee, stand, shelf])
        XCTAssertGreaterThanOrEqual(ideas.count, 3)
        // It always finds somewhere to go.
        XCTAssertTrue(ideas.allSatisfy { $0.leftOut.isEmpty })
    }
}
