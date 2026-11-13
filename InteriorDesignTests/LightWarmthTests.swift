import XCTest
@testable import InteriorDesign

final class LightWarmthTests: XCTestCase {
    // MARK: Reading warmth

    func testKelvinRanges() {
        XCTAssertEqual(LightWarmth(kelvin: 2200), .warm)
        XCTAssertEqual(LightWarmth(kelvin: 3000), .warm)
        XCTAssertEqual(LightWarmth(kelvin: 3500), .neutral)
        XCTAssertEqual(LightWarmth(kelvin: 4000), .neutral)
        XCTAssertEqual(LightWarmth(kelvin: 5000), .cool)
        XCTAssertEqual(LightWarmth(kelvin: 6500), .cool)
    }

    func testParsesKelvinAndWords() {
        XCTAssertEqual(LightWarmth.parse("LED Table Lamp, 2700K Warm"), .warm)
        XCTAssertEqual(LightWarmth.parse("Desk lamp 5000 K"), .cool)
        XCTAssertEqual(LightWarmth.parse("Arc floor lamp, 4000-kelvin bulb"), .neutral)
        XCTAssertEqual(LightWarmth.parse("Bedside lamp with soft white bulb"), .warm)
        XCTAssertEqual(LightWarmth.parse("Daylight reading lamp"), .cool)
        XCTAssertNil(LightWarmth.parse("Linen table lamp"))
        // A model number isn't a color temperature.
        XCTAssertNil(LightWarmth.parse("Lamp model 1234"))
    }

    func testMatchScores() {
        XCTAssertEqual(LightWarmth.match(.warm, room: .warm), 1)
        XCTAssertEqual(LightWarmth.match(.neutral, room: .warm), 0.6)
        XCTAssertEqual(LightWarmth.match(.cool, room: .warm), 0)
        XCTAssertEqual(LightWarmth.match(nil, room: .cool), 0.5)
    }

    // MARK: Room light

    func testMainLightWinsOverLamps() {
        let light = RoomLight(mainLight: .cool, lamps: [.warm, .warm])
        XCTAssertEqual(light.target, .cool)
        XCTAssertTrue(light.isMixed)
    }

    func testLampsDecideWithoutMainLight() {
        XCTAssertEqual(RoomLight(mainLight: nil, lamps: [.cool, .neutral, .cool]).target, .cool)
        // A tie goes to the warmer light.
        XCTAssertEqual(RoomLight(mainLight: nil, lamps: [.cool, .warm]).target, .warm)
        XCTAssertNil(RoomLight(mainLight: nil, lamps: []).target)
        XCTAssertFalse(RoomLight(mainLight: .warm, lamps: [.neutral]).isMixed)
    }

    // MARK: Catalog

    private func lamp(_ id: String, _ light: LightWarmth?, type: ItemType = .tableLamp) -> CatalogProduct {
        CatalogProduct(id: id, name: "Lamp \(id)", price: 40, widthCm: 25, depthCm: 25, heightCm: 50,
                       type: type, lightWarmth: light, rating: 4.2, reviewCount: 100, retailer: "Test")
    }

    func testWarmRoomRanksWarmLampsFirst() {
        let products = [lamp("cool", .cool), lamp("unknown", nil), lamp("warm", .warm)]
        let prefs = ShoppingPreferences(light: RoomLight(mainLight: .warm))
        let ranked = CatalogRanking.rank(products, preferences: prefs, budget: ShoppingBudget())
        XCTAssertEqual(ranked.map(\.id), ["warm", "unknown", "cool"])
    }

    func testCoolRoomRanksCoolLampsFirst() {
        let products = [lamp("warm", .warm, type: .lamp), lamp("cool", .cool, type: .lamp)]
        let prefs = ShoppingPreferences(light: RoomLight(mainLight: .cool))
        XCTAssertEqual(CatalogRanking.rank(products, preferences: prefs, budget: ShoppingBudget()).first?.id, "cool")
    }

    func testRoomColorsPickLampWarmthWhenLightUnknown() {
        let vibe = RoomVibe(colorNames: ["Brown", "Beige"], swatches: [], tone: .warm, lightness: 0.5, colorfulness: 0.3)
        let prefs = ShoppingPreferences(vibe: vibe)
        XCTAssertEqual(prefs.lampWarmth, .warm)
        let ranked = CatalogRanking.rank([lamp("cool", .cool), lamp("warm", .warm)], preferences: prefs, budget: ShoppingBudget())
        XCTAssertEqual(ranked.first?.id, "warm")
    }

    func testLightDoesNotChangeNonLamps() {
        let sofa = CatalogProduct(id: "sofa", name: "Sofa", price: 500, type: .sofa, retailer: "Test")
        let plain = CatalogRanking.score(sofa, preferences: ShoppingPreferences(), budget: ShoppingBudget(), fit: nil)
        let lit = CatalogRanking.score(sofa, preferences: ShoppingPreferences(light: RoomLight(mainLight: .cool)),
                                       budget: ShoppingBudget(), fit: nil)
        XCTAssertEqual(plain, lit)
    }

    func testNormalizerReadsKelvinOnlyForLamps() {
        let lampRaw = RawProduct(id: "a", name: "Table lamp", price: 30, type: "tableLamp", kelvin: 2700, retailer: "T")
        XCTAssertEqual(ProductNormalizer.normalize(lampRaw).lightWarmth, .warm)
        let named = RawProduct(id: "b", name: "Daylight desk lamp", price: 30, retailer: "T")
        XCTAssertEqual(ProductNormalizer.normalize(named).lightWarmth, .cool)
        let rug = RawProduct(id: "c", name: "Warm white rug", price: 30, type: "rug", retailer: "T")
        XCTAssertNil(ProductNormalizer.normalize(rug).lightWarmth)
    }

    func testLiveProductsGetWarmthFromTheirName() {
        let p = CatalogProduct(id: "x", name: "Ceramic table lamp, 3000K warm white", price: 50, retailer: "T")
        XCTAssertEqual(BackendCatalogService.retyped(p).lightWarmth, .warm)
    }

    // MARK: Small decor

    func testWarmLampJoinsTheWarmGroup() throws {
        let a = DecorSurface(id: UUID(), type: .dresser, name: "Dresser A", width: 120, depth: 45, height: 85)
        let b = DecorSurface(id: UUID(), type: .dresser, name: "Dresser B", width: 120, depth: 45, height: 85)
        func piece(_ type: ItemType, _ color: RGB, light: LightWarmth? = nil) -> DecorPiece {
            let s = type.defaultSize
            return DecorPiece(id: UUID(), type: type, name: type.displayName, width: s.width, depth: s.depth,
                              height: s.height, color: color, light: light)
        }
        let plant = piece(.plant, RGB(r: 0.55, g: 0.35, b: 0.2))      // brown pot: warm
        let vase = piece(.vase, RGB(r: 0.2, g: 0.35, b: 0.7))         // blue: cool
        let blackLamp = piece(.tableLamp, RGB(r: 0.05, g: 0.05, b: 0.05), light: .warm)
        XCTAssertEqual(blackLamp.tone, .warm)

        let idea = SmallDecorPlanner.colorGroups([plant, vase, blackLamp], [a, b])
        let host = Dictionary(uniqueKeysWithValues: idea.spots.map { ($0.itemID, $0.hostID) })
        XCTAssertEqual(host[blackLamp.id], host[plant.id])
        XCTAssertNotEqual(host[vase.id], host[plant.id])
    }

    func testLampToneComesFromItsLight() {
        let s = ItemType.tableLamp.defaultSize
        var lamp = DecorPiece(id: UUID(), type: .tableLamp, name: "Lamp", width: s.width, depth: s.depth, height: s.height)
        XCTAssertNil(lamp.tone)
        lamp.light = .cool
        XCTAssertEqual(lamp.tone, .cool)
        // The glow wins over the shade's color.
        lamp.color = RGB(r: 0.55, g: 0.35, b: 0.2)
        XCTAssertEqual(lamp.tone, .cool)
    }
}
