import XCTest
@testable import InteriorDesign

final class WallDecorTests: XCTestCase {
    private let ceiling = 250.0

    // MARK: Keeping pieces on the wall

    func testClampKeepsPieceInsideWall() {
        let piece = WallDecor(kind: .frame, wall: 0, centerX: -50, centerY: 500, widthCm: 40, heightCm: 50)
        let d = WallDecorGeometry.clamped(piece, wallLength: 300, ceiling: ceiling)
        XCTAssertEqual(d.centerX, 20, accuracy: 0.001)
        XCTAssertEqual(d.centerY, 225, accuracy: 0.001)
    }

    func testClampShrinksPieceWiderThanWall() {
        let piece = WallDecor(kind: .shelf, wall: 0, centerX: 50, widthCm: 400)
        let d = WallDecorGeometry.clamped(piece, wallLength: 120, ceiling: ceiling)
        XCTAssertEqual(d.widthCm, 120, accuracy: 0.001)
        XCTAssertEqual(d.centerX, 60, accuracy: 0.001)
    }

    func testPieceStretchesWithItsWall() {
        let old = PlanGeometry.rectangleCorners(width: 400, length: 300)
        let new = PlanGeometry.rectangleCorners(width: 800, length: 300)
        let piece = WallDecor(kind: .frame, wall: 0, centerX: 100)
        let moved = WallDecorGeometry.moved([piece], from: old, to: new, ceiling: ceiling)
        XCTAssertEqual(moved[0].wall, 0)
        XCTAssertEqual(moved[0].centerX, 200, accuracy: 0.001)
    }

    func testPieceFollowsWallWhenCornerAdded() {
        let old = PlanGeometry.rectangleCorners(width: 400, length: 300)
        // A corner added on the top wall at x = 200 splits it in two.
        var new = old
        new.insert(Point2D(x: 200, y: 0), at: 1)
        // A piece on the right wall (wall 1) is now on wall 2.
        let piece = WallDecor(kind: .frame, wall: 1, centerX: 150)
        let moved = WallDecorGeometry.moved([piece], from: old, to: new, ceiling: ceiling)
        XCTAssertEqual(moved[0].wall, 2)
        XCTAssertEqual(moved[0].centerX, 150, accuracy: 0.001)
    }

    func testFreeSpotAvoidsWindowAndOtherPieces() {
        // 400 cm wall: a window from 50 to 170 and a frame from 250 to 350.
        let window = WallRect(minX: 50, minY: 90, maxX: 170, maxY: 210)
        let frame = WallRect(minX: 250, minY: 120, maxX: 350, maxY: 170)
        let x = WallDecorGeometry.freeCenterX(width: 40, height: 145, wallLength: 400, taken: [window, frame])
        // The widest gap is 170 to 250.
        XCTAssertEqual(x, 210, accuracy: 0.001)
    }

    func testFreeSpotIgnoresThingsAtOtherHeights() {
        let outlet = WallRect(minX: 0, minY: 24, maxX: 400, maxY: 36)
        let x = WallDecorGeometry.freeCenterX(width: 40, height: 145, wallLength: 400, taken: [outlet])
        XCTAssertEqual(x, 200, accuracy: 0.001)
    }

    // MARK: Snapping

    func testSnapsToEyeLevelAndWallMiddle() {
        let piece = WallDecor(kind: .frame, wall: 0, centerX: 198, centerY: 147)
        let result = WallDecorGeometry.snapped(piece, wallLength: 400, others: [])
        XCTAssertEqual(result.decor.centerX, 200, accuracy: 0.001)
        XCTAssertEqual(result.decor.centerY, WallDecorGeometry.eyeLevelCm, accuracy: 0.001)
        XCTAssertEqual(result.guides.count, 2)
    }

    func testNoSnapWhenFarFromLines() {
        let piece = WallDecor(kind: .frame, wall: 0, centerX: 100, centerY: 180)
        let result = WallDecorGeometry.snapped(piece, wallLength: 400, others: [])
        XCTAssertEqual(result.decor, piece)
        XCTAssertTrue(result.guides.isEmpty)
    }

    func testSnapsTopEdgeToNeighborTopEdge() {
        // Neighbor 40 × 50 at height 145: top edge at 170.
        let neighbor = WallDecor(kind: .frame, wall: 0, centerX: 100, centerY: 145, widthCm: 40, heightCm: 50)
        // A 30 × 30 piece whose top is at 172, 2 cm off.
        let piece = WallDecor(kind: .frame, wall: 0, centerX: 300, centerY: 157, widthCm: 30, heightCm: 30)
        let result = WallDecorGeometry.snapped(piece, wallLength: 400, others: [neighbor])
        XCTAssertEqual(result.decor.rect.maxY, 170, accuracy: 0.001)
    }

    func testSnapsToMiddleOfFurnitureBelow() {
        let sofa = WallFurniture(id: UUID(), name: "Sofa", rect: WallRect(minX: 50, minY: 0, maxX: 250, maxY: 85))
        let piece = WallDecor(kind: .canvas, wall: 0, centerX: 152, centerY: 180)
        let result = WallDecorGeometry.snapped(piece, wallLength: 600, others: [], furniture: [sofa])
        XCTAssertEqual(result.decor.centerX, 150, accuracy: 0.001)
    }

    // MARK: Furniture against the wall

    func testFindsFurnitureAgainstTopWall() {
        let corners = PlanGeometry.rectangleCorners(width: 500, length: 400)
        let sofa = WallDecorGeometry.FloorBox(id: UUID(), name: "Sofa", minX: 100, minY: 5, maxX: 300, maxY: 95, height: 85)
        let table = WallDecorGeometry.FloorBox(id: UUID(), name: "Table", minX: 200, minY: 200, maxX: 300, maxY: 300, height: 75)
        let found = WallDecorGeometry.furnitureAgainst(wall: 0, corners: corners, boxes: [sofa, table])
        XCTAssertEqual(found.map(\.name), ["Sofa"])
        XCTAssertEqual(found[0].rect, WallRect(minX: 100, minY: 0, maxX: 300, maxY: 85))
    }

    func testFurnitureOnBottomWallSeenFromInside() {
        // Bottom wall runs right to left (corner 2 to corner 3), so when you
        // face it from inside, its left end is the room's right side.
        let corners = PlanGeometry.rectangleCorners(width: 500, length: 400)
        let bed = WallDecorGeometry.FloorBox(id: UUID(), name: "Bed", minX: 350, minY: 200, maxX: 500, maxY: 400, height: 60)
        let found = WallDecorGeometry.furnitureAgainst(wall: 2, corners: corners, boxes: [bed])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(found[0].rect.maxX, 150, accuracy: 0.001)
    }

    func testCenteredAboveFurnitureLeavesGap() {
        let sofa = WallFurniture(id: UUID(), name: "Sofa", rect: WallRect(minX: 50, minY: 0, maxX: 250, maxY: 85))
        let piece = WallDecor(kind: .canvas, wall: 0, centerX: 400, centerY: 100, widthCm: 80, heightCm: 60)
        let d = WallDecorGeometry.centered(piece, above: sofa, ceiling: ceiling)
        XCTAssertEqual(d.centerX, 150, accuracy: 0.001)
        XCTAssertEqual(d.rect.minY, 85 + WallDecorGeometry.gapAboveFurnitureCm, accuracy: 0.001)
    }

    // MARK: Groups

    func testRowSpacesPiecesEvenly() {
        let a = WallDecor(kind: .frame, wall: 0, centerX: 300, widthCm: 40, heightCm: 50)
        let b = WallDecor(kind: .frame, wall: 0, centerX: 100, widthCm: 60, heightCm: 40)
        let row = WallDecorGeometry.row([a, b], centerX: 200, centerY: 145, gap: 10)
        // Total width 40 + 10 + 60 = 110, from 145 to 255. b stays on the left.
        XCTAssertEqual(row.map(\.id), [b.id, a.id])
        XCTAssertEqual(row[0].rect.minX, 145, accuracy: 0.001)
        XCTAssertEqual(row[1].rect.minX - row[0].rect.maxX, 10, accuracy: 0.001)
        XCTAssertEqual(row[1].rect.maxX, 255, accuracy: 0.001)
        XCTAssertTrue(row.allSatisfy { $0.centerY == 145 })
    }

    // MARK: Problems

    func testWarnsWhenCoveringWindowOrOverlapping() {
        let window = FixedFeature(kind: .window, wall: 0, offsetCm: 200, widthCm: 120)
        let outlet = FixedFeature(kind: .outlet, wall: 0, offsetCm: 200, widthCm: 10)
        let other = WallDecor(kind: .frame, name: "Print", wall: 0, centerX: 230, centerY: 150)
        let piece = WallDecor(kind: .mirror, wall: 0, centerX: 200, centerY: 150)
        let problems = WallDecorGeometry.problems(for: piece, features: [window, outlet], others: [other, piece], ceiling: ceiling)
        XCTAssertEqual(problems, ["Covers the window", "Overlaps Print"])
    }

    func testNoProblemsForClearSpot() {
        let door = FixedFeature(kind: .door, wall: 0, offsetCm: 50, widthCm: 90)
        let piece = WallDecor(kind: .frame, wall: 0, centerX: 250)
        XCTAssertTrue(WallDecorGeometry.problems(for: piece, features: [door], others: [], ceiling: ceiling).isEmpty)
    }

    func testOldSavedDecorStillLoads() throws {
        let json = #"{"kind":"poster","wall":1,"centerX":120}"#.data(using: .utf8)!
        let d = try JSONDecoder().decode(WallDecor.self, from: json)
        XCTAssertEqual(d.kind, .poster)
        XCTAssertEqual(d.name, "Poster")
        XCTAssertEqual(d.centerY, WallDecorGeometry.eyeLevelCm)
        XCTAssertEqual(d.widthCm, DecorKind.poster.defaultSize.width)
    }
}
