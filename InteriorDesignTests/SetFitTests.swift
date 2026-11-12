import XCTest
import simd
@testable import InteriorDesign

final class SetFitTests: XCTestCase {
    /// A solid box as triangles (two per face).
    private func box(center c: SIMD3<Float>, size s: SIMD3<Float>) -> (positions: [SIMD3<Float>], indices: [UInt32]) {
        let h = s / 2
        let p: [SIMD3<Float>] = [
            [-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1],
            [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1],
        ].map { c + $0 * h }
        let faces: [UInt32] = [0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4,
                               3, 7, 6, 3, 6, 2, 0, 4, 7, 0, 7, 3, 1, 2, 6, 1, 6, 5]
        return (p, faces)
    }

    /// A dining table (1.2 × 0.8 m top at 0.75 m) with a chair on each long
    /// side, all turned 30° the way an AI model might come out.
    private func diningSet(turned degrees: Float) -> [(positions: [SIMD3<Float>], indices: [UInt32])] {
        var parts = [box(center: [0, 0.74, 0], size: [1.2, 0.03, 0.8])]
        for x: Float in [-0.6, 0.6] {
            for z: Float in [-0.25, 0.25] { parts.append(box(center: [x * 0.9, 0.36, z * 1.5 + 0], size: [0.04, 0.72, 0.04])) }
        }
        for z: Float in [-0.7, 0.7] {
            parts.append(box(center: [0, 0.45, z], size: [0.45, 0.04, 0.45]))          // seat
            parts.append(box(center: [0, 0.68, z + (z > 0 ? 0.2 : -0.2)], size: [0.45, 0.45, 0.04])) // back
        }
        let turn = simd_quatf(angle: degrees * .pi / 180, axis: [0, 1, 0])
        return parts.map { ($0.positions.map { turn.act($0) }, $0.indices) }
    }

    func testRecognizesSets() {
        XCTAssertTrue(ModelFit.isSet(name: "6 Pc Dinette Set"))
        XCTAssertTrue(ModelFit.isSet(name: "5-Piece Dining Table with 4 Padded Chairs"))
        XCTAssertTrue(ModelFit.isSet(name: "Oak table with chairs"))
        XCTAssertFalse(ModelFit.isSet(name: "Upholstered Dining Bench"))
        XCTAssertFalse(ModelFit.isSet(name: "Sunset Oak Desk"), "\"set\" inside another word")
    }

    func testSizesASetByItsTableAndSquaresIt() throws {
        // Listed size: the table only, 1.2 × 0.75 × 0.8 m, at half scale in the model.
        let model: [(positions: [SIMD3<Float>], indices: [UInt32])] = diningSet(turned: 30).map { (positions: $0.positions.map { $0 * 0.5 }, indices: $0.indices) }
        let placement = try XCTUnwrap(ModelFit.setPlacement(meshes: model, target: [1.2, 0.75, 0.8]))
        XCTAssertEqual(placement.scale, 2, accuracy: 0.1, "the table comes out at its listed size")
        // After the turn, the table top's long side runs along x.
        let turn = simd_quatf(angle: placement.turn, axis: [0, 1, 0])
        let top = model[0].positions.map { turn.act($0) }
        let xs = top.map(\.x), zs = top.map(\.z)
        XCTAssertEqual(xs.max()! - xs.min()!, 0.6, accuracy: 0.03)
        XCTAssertEqual(zs.max()! - zs.min()!, 0.4, accuracy: 0.03)
        XCTAssertEqual(placement.tableCenter.x, 0, accuracy: 0.02)
        XCTAssertEqual(placement.tableCenter.y, 0, accuracy: 0.02)
    }

    func testNoTableMeansUsualSizing() {
        // A lone tall panel: nothing flat and high enough to call a table.
        XCTAssertNil(ModelFit.setPlacement(meshes: [box(center: [0, 0.5, 0], size: [0.4, 1.0, 0.04])], target: [1, 1, 1]))
    }
}
