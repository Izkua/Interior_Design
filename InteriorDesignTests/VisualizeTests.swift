import XCTest
@testable import InteriorDesign

final class VisualizeTests: XCTestCase {
    func testRequestDescribesTheLayout() throws {
        let room = Room(name: "Den", width: 400, length: 300)
        let sofa = LayoutItem(id: UUID(), type: .sofa, name: "Sofa", width: 200, depth: 90, height: 85)
        let placement = ItemPlacement(itemID: sofa.id, x: 200, y: 50, rotation: 0)
        let request = VisualizeRequest(room: room, placements: [placement], items: [sofa], style: .warm, roomPhoto: nil)
        XCTAssertEqual(request.pieces.count, 1)
        XCTAssertEqual(request.pieces[0].type, "sofa")
        XCTAssertNil(request.roomPhoto)

        // It encodes to the field names the backend expects.
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(request), encoding: .utf8))
        for key in ["\"style\":\"warm\"", "\"corners\"", "\"pieces\"", "\"widthCm\""] {
            XCTAssertTrue(json.contains(key), key)
        }
    }

    func testRoomPhotoIsShrunk() throws {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
        }()).image { _ in UIColor.gray.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 3000, height: 2000)) }
        let request = VisualizeRequest(room: Room(name: "R", width: 300, length: 300), placements: [], items: [], style: .modern, roomPhoto: big)
        let data = try XCTUnwrap(request.roomPhoto.flatMap { Data(base64Encoded: $0) })
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertLessThanOrEqual(max(image.size.width * image.scale, image.size.height * image.scale), 1024)
    }

    func testEveryPictureIsLabeled() {
        let plain = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { _ in
            UIColor.white.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        let stamped = AIImageLabel.stamped(plain)
        XCTAssertEqual(stamped.size, plain.size)
        XCTAssertNotEqual(stamped.pngData(), plain.pngData())   // the label band was drawn
        XCTAssertTrue(AIImageLabel.text.hasPrefix("AI-generated inspiration"))
    }

    func testErrorsNeverBlameThePerson() {
        // Failures say nothing was used up, matching the backend rule that
        // only successful pictures count.
        XCTAssertTrue(VisualizeError.timedOut.errorDescription!.contains("didn't count"))
        XCTAssertTrue(VisualizeError.offline.errorDescription!.contains("nothing was used up"))
        XCTAssertTrue(VisualizeError.failed.errorDescription!.contains("Nothing was used up"))
    }

    @MainActor
    func testButtonIsOffUntilSwitchedOn() {
        UserDefaults.standard.set(false, forKey: SettingsKey.demoAIFeatures)
        XCTAssertFalse(BackendConfig.visualizeEnabled)
        XCTAssertEqual(VisualizeAvailability.current, .comingSoon)
        XCTAssertFalse(VisualizeAvailability.current.canOpen)
    }
}
