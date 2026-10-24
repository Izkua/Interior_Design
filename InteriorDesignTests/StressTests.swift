import XCTest
@testable import InteriorDesign

/// Unhappy paths from the Week 6 plan: very small and very large rooms,
/// lots of furniture, and products with missing data.
final class StressTests: XCTestCase {
    private func item(_ type: ItemType, _ w: Double, _ d: Double, _ h: Double) -> LayoutItem {
        LayoutItem(id: UUID(), type: type, name: type.displayName, width: w, depth: d, height: h)
    }

    /// 30 pieces of everyday furniture.
    private var thirtyItems: [LayoutItem] {
        let kinds: [(ItemType, Double, Double, Double)] = [
            (.sofa, 210, 90, 85), (.chair, 80, 80, 90), (.chair, 50, 50, 90), (.table, 110, 60, 42),
            (.tvStand, 150, 40, 50), (.shelf, 80, 30, 180), (.lamp, 30, 30, 160), (.dresser, 120, 45, 85),
            (.desk, 120, 60, 75), (.rug, 200, 140, 1),
        ]
        return (0..<30).map { i in let k = kinds[i % kinds.count]; return item(k.0, k.1, k.2, k.3) }
    }

    func testThirtyItemsInALargeRoomStaysFast() {
        let room = LayoutRoom(
            corners: PlanGeometry.rectangleCorners(width: 1200, length: 900),
            features: [FixedFeature(kind: .door, wall: 2, offsetCm: 100, widthCm: 90)]
        )
        let started = Date()
        let layouts = LayoutEngine.suggest(room: room, items: thirtyItems)
        let seconds = Date().timeIntervalSince(started)
        XCTAssertFalse(layouts.isEmpty)
        // Debug test builds run several times slower than the app; the
        // engine's own time budget keeps the app well under this.
        XCTAssertLessThan(seconds, 6, "took \(seconds) s")
    }

    func testVeryLargeRoomStaysFast() {
        // 30 m × 25 m, about a small warehouse.
        let room = LayoutRoom(corners: PlanGeometry.rectangleCorners(width: 3000, length: 2500),
                              features: [FixedFeature(kind: .door, wall: 2, offsetCm: 200, widthCm: 90)])
        let items = Array(thirtyItems.prefix(10))
        let started = Date()
        let layouts = LayoutEngine.suggest(room: room, items: items)
        XCTAssertFalse(layouts.isEmpty)
        XCTAssertLessThan(Date().timeIntervalSince(started), 6)
    }

    func testVerySmallRoomFitsWhatItCan() throws {
        // A 1.5 m × 1.5 m box room: a lamp fits, a sofa can't.
        let room = LayoutRoom(corners: PlanGeometry.rectangleCorners(width: 150, length: 150),
                              features: [FixedFeature(kind: .door, wall: 2, offsetCm: 75, widthCm: 70)])
        let lamp = item(.lamp, 30, 30, 150), sofa = item(.sofa, 210, 90, 85)
        let best = try XCTUnwrap(LayoutEngine.suggest(room: room, items: [lamp, sofa]).first)
        XCTAssertTrue(best.leftOut.contains(sofa.id))
    }

    func testEmptyInputsDoNotCrash() {
        let room = LayoutRoom(corners: PlanGeometry.rectangleCorners(width: 300, length: 300))
        XCTAssertTrue(LayoutEngine.suggest(room: room, items: []).isEmpty)
        let flat = LayoutRoom(corners: [Point2D(x: 0, y: 0), Point2D(x: 100, y: 0)])
        XCTAssertTrue(LayoutEngine.suggest(room: flat, items: [item(.lamp, 30, 30, 150)]).isEmpty)
    }

    func testProductWithMissingDataStillShows() throws {
        let json = #"[{"id":"x","name":"Mystery chair","price":0,"retailer":"Shop"}]"#
        let raw = try JSONDecoder().decode([RawProduct].self, from: Data(json.utf8))
        let product = ProductNormalizer.normalize(raw[0])
        XCTAssertFalse(product.hasDimensions)
        XCTAssertNil(product.rating)
        XCTAssertNil(product.url)
        XCTAssertEqual(product.type, .chair)
        let room = LayoutRoom(corners: PlanGeometry.rectangleCorners(width: 300, length: 300))
        XCTAssertEqual(FitCheck.check(product, room: room, furniture: []), .unknownSize)
    }
}
