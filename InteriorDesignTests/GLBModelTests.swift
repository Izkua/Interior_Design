import XCTest
import simd
@testable import InteriorDesign

final class GLBModelTests: XCTestCase {
    /// A GLB with one triangle, a node that moves it up 1 m, and UVs.
    private func triangleGLB(indexType: Int = 5123) -> Data {
        var bin = Data()
        func append<T>(_ values: [T]) { values.withUnsafeBytes { bin.append(contentsOf: $0) } }
        append([Float(0), 0, 0, 1, 0, 0, 0, 0, 1])             // positions, 36 bytes
        append([Float(0), 0, 1, 0, 1, 0])                      // uvs, 24 bytes
        if indexType == 5125 { append([UInt32(0), 1, 2]) } else { append([UInt16(0), 1, 2]); append([UInt16(0)]) }
        let indexLength = indexType == 5125 ? 12 : 6
        let json = """
        {"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],
         "nodes":[{"children":[1],"translation":[0,1,0]},{"mesh":0}],
         "meshes":[{"primitives":[{"attributes":{"POSITION":0,"TEXCOORD_0":1},"indices":2,"material":0}]}],
         "materials":[{"pbrMetallicRoughness":{"baseColorFactor":[0.5,0.25,1,1],"metallicFactor":0,"roughnessFactor":0.7}}],
         "accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"},
                      {"bufferView":1,"componentType":5126,"count":3,"type":"VEC2"},
                      {"bufferView":2,"componentType":\(indexType),"count":3,"type":"SCALAR"}],
         "bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":24},
                        {"buffer":0,"byteOffset":60,"byteLength":\(indexLength)}],
         "buffers":[{"byteLength":\(bin.count)}]}
        """
        var jsonData = Data(json.utf8)
        while jsonData.count % 4 != 0 { jsonData.append(0x20) }
        while bin.count % 4 != 0 { bin.append(0) }
        var out = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        u32(0x4654_6C67); u32(2); u32(UInt32(12 + 8 + jsonData.count + 8 + bin.count))
        u32(UInt32(jsonData.count)); u32(0x4E4F_534A); out.append(jsonData)
        u32(UInt32(bin.count)); u32(0x004E_4942); out.append(bin)
        return out
    }

    func testReadsATriangleWithItsPlacement() throws {
        let model = try GLBModel(data: triangleGLB())
        XCTAssertEqual(model.meshes.count, 1)
        let mesh = model.meshes[0]
        XCTAssertEqual(mesh.positions, [[0, 1, 0], [1, 1, 0], [0, 1, 1]], "moved up 1 m by its parent node")
        XCTAssertEqual(mesh.indices, [0, 1, 2])
        XCTAssertEqual(mesh.uvs?.count, 3)
        XCTAssertEqual(model.materials.first?.baseColor, [0.5, 0.25, 1, 1])
        XCTAssertEqual(model.materials.first?.roughness, 0.7)
    }

    func testReadsBigIndexNumbers() throws {
        XCTAssertEqual(try GLBModel(data: triangleGLB(indexType: 5125)).meshes[0].indices, [0, 1, 2])
    }

    func testRejectsFilesThatArentGLB() {
        XCTAssertThrowsError(try GLBModel(data: Data("not a model".utf8)))
        var broken = triangleGLB()
        broken.removeLast(20)
        XCTAssertThrowsError(try GLBModel(data: broken))
    }

    @MainActor
    func testMakesARealityKitEntity() throws {
        let entity = try GLBModel(data: triangleGLB()).entity()
        XCTAssertEqual(entity.children.count, 1)
    }
}
