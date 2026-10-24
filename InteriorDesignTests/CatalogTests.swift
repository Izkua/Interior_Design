import XCTest
@testable import InteriorDesign

final class CatalogTests: XCTestCase {
    private func product(
        _ id: String, _ price: Double, type: ItemType? = .sofa,
        size: (Double, Double, Double)? = (200, 90, 85),
        styles: [String] = [], materials: [String] = [], rating: Double? = 4, reviews: Int = 100
    ) -> CatalogProduct {
        CatalogProduct(
            id: id, name: "Product \(id)", price: price,
            widthCm: size?.0, depthCm: size?.1, heightCm: size?.2,
            type: type, materials: materials, styles: styles,
            rating: rating, reviewCount: reviews, retailer: "Test"
        )
    }

    // MARK: Normalization

    func testInchesBecomeCentimeters() {
        let raw = RawProduct(
            id: "1", name: " Oak table ", price: 100, currency: nil,
            size: .init(width: 43, depth: 24, height: 17, unit: "in"),
            type: nil, materials: nil, styles: nil, colors: nil, rating: 7,
            reviewCount: nil, imageURL: nil, retailer: "R", url: nil, isSample: nil
        )
        let p = ProductNormalizer.normalize(raw)
        XCTAssertEqual(p.widthCm ?? 0, 109.22, accuracy: 0.01)
        XCTAssertEqual(p.name, "Oak table")
        XCTAssertEqual(p.type, .table)  // from the name
        XCTAssertEqual(p.rating, 5)     // clamped to 0–5
        XCTAssertEqual(p.currency, "USD")
    }

    func testImpossibleSizesAreDropped() {
        let raw = RawProduct(
            id: "1", name: "Rug", price: 50, currency: "USD",
            size: .init(width: 0, depth: -3, height: 5000, unit: "cm"),
            type: "rug", materials: nil, styles: nil, colors: nil, rating: nil,
            reviewCount: nil, imageURL: nil, retailer: "R", url: nil, isSample: nil
        )
        let p = ProductNormalizer.normalize(raw)
        XCTAssertNil(p.widthCm)
        XCTAssertNil(p.depthCm)
        XCTAssertNil(p.heightCm)
        XCTAssertFalse(p.hasDimensions)
    }

    func testTypeFromWords() {
        XCTAssertEqual(ProductNormalizer.itemType(nil, name: "Modern 3-Seat Sectional"), .sofa)
        XCTAssertEqual(ProductNormalizer.itemType("Media console", name: "Walnut"), .tvStand)
        XCTAssertEqual(ProductNormalizer.itemType(nil, name: "Mid-century accent chair"), .chair)
        XCTAssertEqual(ProductNormalizer.itemType("desk", name: "Anything"), .desk)
        XCTAssertNil(ProductNormalizer.itemType(nil, name: "Throw pillow"))
    }

    func testCuratedListLoadsAndIsMarkedSample() throws {
        let url = Bundle(for: CatalogTests.self).url(forResource: "curated-products", withExtension: "json")
            ?? Bundle.main.url(forResource: "curated-products", withExtension: "json")
        let products = CuratedCatalogService.load(from: url)
        XCTAssertFalse(products.isEmpty)
        // Placeholders must never pretend to be real products.
        XCTAssertTrue(products.allSatisfy { $0.isSample && $0.url == nil })
        // The list includes one without a size, which must not count as sized.
        XCTAssertTrue(products.contains { !$0.hasDimensions })
    }

    // MARK: Budget and filters

    func testBudgetLimits() {
        var budget = ShoppingBudget(total: 1_000, perItem: [.sofa: 700], committed: 200)
        XCTAssertEqual(budget.remaining, 800)
        XCTAssertEqual(budget.limit(for: .sofa), 700)   // its own cap is lower
        XCTAssertEqual(budget.limit(for: .lamp), 800)   // only the money left
        budget.committed = 950
        XCTAssertEqual(budget.limit(for: .sofa), 50)
        XCTAssertNil(ShoppingBudget().limit(for: .sofa))
    }

    func testFilterByBudgetAndPrice() {
        let items = [product("cheap", 300), product("mid", 650), product("pricey", 1_200)]
        let budget = ShoppingBudget(total: 1_000, perItem: [.sofa: 700])
        let result = CatalogRanking.filter(items, query: CatalogQuery(), budget: budget)
        XCTAssertEqual(result.map(\.id), ["cheap", "mid"])

        var query = CatalogQuery()
        query.minPrice = 400
        XCTAssertEqual(CatalogRanking.filter(items, query: query, budget: budget).map(\.id), ["mid"])
    }

    func testFilterByRatingTypeAndPreferences() {
        let items = [
            product("a", 100, type: .lamp, materials: ["Metal"], rating: 4.5),
            product("b", 100, type: .lamp, materials: ["Wood"], rating: 3.0),
            product("c", 100, type: .lamp, materials: ["Metal"], rating: nil),
            product("d", 100, type: .sofa, materials: ["Metal"], rating: 4.8),
        ]
        var query = CatalogQuery()
        query.type = .lamp
        query.minRating = 4
        query.materials = ["metal"]
        XCTAssertEqual(CatalogRanking.filter(items, query: query, budget: ShoppingBudget()).map(\.id), ["a"])
    }

    func testTextSearchMatchesAllWords() {
        var query = CatalogQuery()
        query.text = "product B"
        let items = [product("a", 10), product("b", 10)]
        XCTAssertEqual(CatalogRanking.filter(items, query: query, budget: ShoppingBudget()).map(\.id), ["b"])
    }

    // MARK: Ranking

    func testRankingPrefersFitThenTaste() {
        let fits = product("fits", 500)
        let liked = product("liked", 500, styles: ["Modern"])
        let tooBig = product("tooBig", 300, styles: ["Modern"], materials: ["Wood"])
        let fit: [String: FitResult] = [
            "fits": .fits(ItemPlacement(itemID: UUID(), x: 0, y: 0, rotation: 0)),
            "liked": .fits(ItemPlacement(itemID: UUID(), x: 0, y: 0, rotation: 0)),
            "tooBig": .doesNotFit(reason: "x"),
        ]
        let ranked = CatalogRanking.rank(
            [tooBig, fits, liked],
            preferences: ShoppingPreferences(styles: ["Modern"]),
            budget: ShoppingBudget(),
            fit: fit
        )
        XCTAssertEqual(ranked.map(\.id), ["liked", "fits", "tooBig"])
    }

    func testRatingCountsMoreWithMoreReviews() {
        let many = product("many", 100, rating: 4.5, reviews: 500)
        let few = product("few", 100, rating: 5.0, reviews: 2)
        let ranked = CatalogRanking.rank([few, many], preferences: ShoppingPreferences(), budget: ShoppingBudget())
        XCTAssertEqual(ranked.first?.id, "many")
    }

    // MARK: Fit check

    private var room: LayoutRoom {
        LayoutRoom(
            corners: PlanGeometry.rectangleCorners(width: 420, length: 360),
            features: [FixedFeature(kind: .door, wall: 2, offsetCm: 80, widthCm: 90)]
        )
    }

    func testProductWithoutSizeIsNeverMarkedFitting() {
        let result = FitCheck.check(product("x", 100, size: nil), room: room, furniture: [])
        XCTAssertEqual(result, .unknownSize)
        XCTAssertFalse(result.fits)
    }

    func testSofaFitsEmptyRoom() {
        XCTAssertTrue(FitCheck.check(product("s", 500), room: room, furniture: []).fits)
    }

    func testTooBigForRoom() {
        let huge = product("h", 500, size: (500, 400, 80))
        guard case .doesNotFit(let reason) = FitCheck.check(huge, room: room, furniture: []) else {
            return XCTFail("should not fit")
        }
        XCTAssertTrue(reason.contains("bigger than the room"))
    }

    func testNoFreeSpotNextToFurniture() {
        // Two big wardrobes against the long walls leave a corridor too
        // narrow for a 200 × 90 sofa plus its walking path.
        let small = LayoutRoom(
            corners: PlanGeometry.rectangleCorners(width: 300, length: 260),
            features: [FixedFeature(kind: .door, wall: 2, offsetCm: 150, widthCm: 80)]
        )
        let wardrobe = LayoutItem(id: UUID(), type: .dresser, name: "Wardrobe", width: 300, depth: 70, height: 200)
        let bed = LayoutItem(id: UUID(), type: .bed, name: "Bed", width: 200, depth: 90, height: 50)
        let furniture = [
            PlacedItem(item: wardrobe, placement: ItemPlacement(itemID: wardrobe.id, x: 150, y: 36, rotation: 0)),
            PlacedItem(item: bed, placement: ItemPlacement(itemID: bed.id, x: 100, y: 150, rotation: 0)),
        ]
        let result = FitCheck.check(product("s", 500), room: small, furniture: furniture)
        XCTAssertFalse(result.fits)
        // But the same sofa would fit if the room were empty.
        XCTAssertTrue(FitCheck.check(product("s", 500), room: small, furniture: []).fits)
    }

    // MARK: Live catalog with backup

    private struct Failing: CatalogService {
        func search(_ query: CatalogQuery) async throws -> [CatalogProduct] { throw CatalogError.offline }
    }

    func testFallsBackToCuratedListWhenOffline() async {
        let curated = CuratedCatalogService(products: [product("c", 100)])
        let service = FallbackCatalogService(primary: Failing(), backup: curated)
        let result = await service.search(CatalogQuery())
        XCTAssertEqual(result.source, .curated)
        XCTAssertEqual(result.products.map(\.id), ["c"])
    }

    func testUsesLiveCatalogWhenItAnswers() async {
        let live = CuratedCatalogService(products: [product("live", 100)])
        let service = FallbackCatalogService(primary: live, backup: CuratedCatalogService(products: []))
        let result = await service.search(CatalogQuery())
        XCTAssertEqual(result.source, .live)
        XCTAssertEqual(result.products.map(\.id), ["live"])
    }
}
