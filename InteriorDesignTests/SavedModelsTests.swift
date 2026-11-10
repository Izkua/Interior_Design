import XCTest
@testable import InteriorDesign

@MainActor
final class SavedModelsTests: XCTestCase {
    func testRemembersNewestFirstAndSurvivesRestart() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var a = CatalogProduct.placeholder; a.id = "a"
        var b = CatalogProduct.placeholder; b.id = "b"

        let models = SavedModels(folder: folder)
        models.remember(a)
        models.remember(b)
        models.remember(a)   // opened again: moves to the top, no duplicate
        XCTAssertEqual(models.entries.map(\.id), ["a", "b"])

        let reopened = SavedModels(folder: folder)
        XCTAssertEqual(reopened.entries.map(\.id), ["a", "b"])

        let file = try XCTUnwrap(reopened.modelFile("b"))
        try Data("glTF".utf8).write(to: file)
        reopened.remove("b")
        XCTAssertEqual(reopened.entries.map(\.id), ["a"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "model file deleted too")
        XCTAssertNil(reopened.modelFile("../x"), "only safe ids become file names")
    }
}
