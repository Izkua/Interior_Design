import Foundation
import simd
import UIKit
import RealityKit

/// Reads a GLB file (binary glTF, the 3D format AI model makers return)
/// into plain meshes, so RealityKit can show it. iOS can't open GLB by
/// itself, and this small reader covers what Stability AI's 3D models produce
/// (triangle meshes with a color texture), so no extra library is needed.
///
/// glTF is Y-up, in meters, with the front toward +Z: the same as RealityKit.
struct GLBModel {
    struct Mesh {
        /// Already moved into place (node transforms applied).
        var positions: [SIMD3<Float>]
        var normals: [SIMD3<Float>]?
        /// glTF style: (0, 0) is the image's top-left corner.
        var uvs: [SIMD2<Float>]?
        var indices: [UInt32]
        var material: Int?
    }

    struct Material {
        var baseColor: SIMD4<Float> = [1, 1, 1, 1]
        /// PNG or JPEG bytes.
        var baseColorImage: Data?
        var roughness: Float = 1
        var metallic: Float = 0
    }

    var meshes: [Mesh] = []
    var materials: [Material] = []

    enum ReadError: Error { case notGLB, badJSON, badData }

    init(data: Data) throws {
        let bytes = [UInt8](data)
        func u32(_ at: Int) -> UInt32 {
            guard at + 4 <= bytes.count else { return 0 }
            return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }
        // Header: "glTF", version 2, total length; then chunks.
        guard bytes.count >= 20, u32(0) == 0x4654_6C67, u32(4) == 2 else { throw ReadError.notGLB }
        var json: Data?
        var binary: [UInt8] = []
        var offset = 12
        while offset + 8 <= bytes.count {
            let length = Int(u32(offset)), type = u32(offset + 4)
            let start = offset + 8, end = start + length
            guard end <= bytes.count else { throw ReadError.badData }
            if type == 0x4E4F_534A { json = Data(bytes[start..<end]) }       // "JSON"
            if type == 0x004E_4942 { binary = Array(bytes[start..<end]) }    // "BIN\0"
            offset = end
        }
        guard let json, let doc = try? JSONDecoder().decode(Document.self, from: json) else { throw ReadError.badJSON }
        try self.init(doc, binary: binary)
    }

    private init(_ doc: Document, binary: [UInt8]) throws {
        func view(_ index: Int) throws -> (bytes: ArraySlice<UInt8>, stride: Int?) {
            guard let v = doc.bufferViews?[safe: index], v.buffer == 0 else { throw ReadError.badData }
            let start = v.byteOffset ?? 0, end = start + v.byteLength
            guard end <= binary.count else { throw ReadError.badData }
            return (binary[start..<end], v.byteStride)
        }

        /// One accessor's values as floats, `width` per element.
        func floats(_ index: Int, width: Int) throws -> [Float] {
            guard let a = doc.accessors?[safe: index], let viewIndex = a.bufferView else { throw ReadError.badData }
            let (slice, stride) = try view(viewIndex)
            let size: Int, read: (Int) -> Float
            let base = slice.startIndex + (a.byteOffset ?? 0)
            func le16(_ i: Int) -> UInt16 { UInt16(slice[i]) | UInt16(slice[i + 1]) << 8 }
            switch a.componentType {
            case 5126:
                size = 4
                read = { i in Float(bitPattern: UInt32(slice[i]) | UInt32(slice[i + 1]) << 8 | UInt32(slice[i + 2]) << 16 | UInt32(slice[i + 3]) << 24) }
            case 5123:
                size = 2
                read = { i in a.normalized == true ? Float(le16(i)) / 65535 : Float(le16(i)) }
            case 5121:
                size = 1
                read = { i in a.normalized == true ? Float(slice[i]) / 255 : Float(slice[i]) }
            default: throw ReadError.badData
            }
            let step = stride ?? size * width
            var out: [Float] = []
            out.reserveCapacity(a.count * width)
            for element in 0..<a.count {
                for c in 0..<width {
                    let i = base + element * step + c * size
                    guard i + size <= slice.endIndex else { throw ReadError.badData }
                    out.append(read(i))
                }
            }
            return out
        }

        func indices(_ index: Int) throws -> [UInt32] {
            guard let a = doc.accessors?[safe: index], let viewIndex = a.bufferView else { throw ReadError.badData }
            let (slice, _) = try view(viewIndex)
            let base = slice.startIndex + (a.byteOffset ?? 0)
            let size = a.componentType == 5125 ? 4 : a.componentType == 5123 ? 2 : 1
            guard base + a.count * size <= slice.endIndex else { throw ReadError.badData }
            return (0..<a.count).map { n in
                let i = base + n * size
                switch size {
                case 4: return UInt32(slice[i]) | UInt32(slice[i + 1]) << 8 | UInt32(slice[i + 2]) << 16 | UInt32(slice[i + 3]) << 24
                case 2: return UInt32(slice[i]) | UInt32(slice[i + 1]) << 8
                default: return UInt32(slice[i])
                }
            }
        }

        // Materials and their color pictures.
        materials = (doc.materials ?? []).map { m in
            var material = Material()
            if let pbr = m.pbrMetallicRoughness {
                if let f = pbr.baseColorFactor, f.count == 4 { material.baseColor = [f[0], f[1], f[2], f[3]] }
                material.roughness = pbr.roughnessFactor ?? 1
                material.metallic = pbr.metallicFactor ?? 1
                if let t = pbr.baseColorTexture?.index,
                   let source = doc.textures?[safe: t]?.source,
                   let image = doc.images?[safe: source], let v = image.bufferView,
                   let bytes = try? view(v).bytes {
                    material.baseColorImage = Data(bytes)
                }
            }
            return material
        }

        // Walk the scene, applying each node's placement to its meshes.
        let roots = doc.scenes?[safe: doc.scene ?? 0]?.nodes ?? Array(0..<(doc.nodes?.count ?? 0))
        var visited = Set<Int>()
        func walk(_ index: Int, _ parent: simd_float4x4) throws {
            guard let node = doc.nodes?[safe: index], visited.insert(index).inserted else { return }
            let transform = parent * node.localTransform
            if let meshIndex = node.mesh, let mesh = doc.meshes?[safe: meshIndex] {
                let normalMatrix = simd_float3x3(
                    simd_make_float3(transform.columns.0), simd_make_float3(transform.columns.1), simd_make_float3(transform.columns.2)
                ).inverse.transpose
                for p in mesh.primitives where (p.mode ?? 4) == 4 {
                    guard let positionIndex = p.attributes["POSITION"] else { continue }
                    let raw = try floats(positionIndex, width: 3)
                    let positions = stride(from: 0, to: raw.count, by: 3).map { i -> SIMD3<Float> in
                        simd_make_float3(transform * SIMD4<Float>(raw[i], raw[i + 1], raw[i + 2], 1))
                    }
                    let normals = try p.attributes["NORMAL"].map { n -> [SIMD3<Float>] in
                        let raw = try floats(n, width: 3)
                        return stride(from: 0, to: raw.count, by: 3).map { i in
                            simd_normalize(normalMatrix * SIMD3<Float>(raw[i], raw[i + 1], raw[i + 2]))
                        }
                    }
                    let uvs = try p.attributes["TEXCOORD_0"].map { t -> [SIMD2<Float>] in
                        let raw = try floats(t, width: 2)
                        return stride(from: 0, to: raw.count, by: 2).map { SIMD2(raw[$0], raw[$0 + 1]) }
                    }
                    let list = try p.indices.map(indices) ?? (0..<UInt32(positions.count)).map { $0 }
                    guard list.allSatisfy({ Int($0) < positions.count }) else { throw ReadError.badData }
                    meshes.append(Mesh(positions: positions, normals: normals?.count == positions.count ? normals : nil,
                                       uvs: uvs?.count == positions.count ? uvs : nil, indices: list, material: p.material))
                }
            }
            for child in node.children ?? [] { try walk(child, transform) }
        }
        for root in roots { try walk(root, matrix_identity_float4x4) }
        guard !meshes.isEmpty else { throw ReadError.badData }
    }

    // MARK: Showing it

    /// A RealityKit entity for the model.
    @MainActor
    func entity() throws -> Entity {
        let root = Entity()
        var made: [Int: RealityKit.Material] = [:]
        func material(_ index: Int?) -> RealityKit.Material {
            if let index, let cached = made[index] { return cached }
            let source = index.flatMap { materials[safe: $0] } ?? Material()
            var pbr = PhysicallyBasedMaterial()
            let tint = UIColor(red: CGFloat(source.baseColor.x), green: CGFloat(source.baseColor.y),
                               blue: CGFloat(source.baseColor.z), alpha: 1)
            if let data = source.baseColorImage, let image = UIImage(data: data)?.cgImage,
               let texture = try? TextureResource.generate(from: image, options: .init(semantic: .color)) {
                pbr.baseColor = .init(tint: tint, texture: .init(texture))
            } else {
                pbr.baseColor = .init(tint: tint)
            }
            pbr.roughness = .init(floatLiteral: source.roughness)
            pbr.metallic = .init(floatLiteral: source.metallic)
            if let index { made[index] = pbr }
            return pbr
        }
        for (n, mesh) in meshes.enumerated() {
            var descriptor = MeshDescriptor(name: "mesh\(n)")
            descriptor.positions = MeshBuffers.Positions(mesh.positions)
            if let normals = mesh.normals { descriptor.normals = MeshBuffers.Normals(normals) }
            // RealityKit counts texture rows from the bottom.
            if let uvs = mesh.uvs { descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs.map { [$0.x, 1 - $0.y] }) }
            descriptor.primitives = .triangles(mesh.indices)
            let resource = try MeshResource.generate(from: [descriptor])
            root.addChild(ModelEntity(mesh: resource, materials: [material(mesh.material)]))
        }
        return root
    }
}

// MARK: - The glTF JSON, just the parts we use

private struct Document: Decodable {
    var scene: Int?
    var scenes: [Scene]?
    var nodes: [Node]?
    var meshes: [MeshJSON]?
    var accessors: [Accessor]?
    var bufferViews: [BufferView]?
    var materials: [MaterialJSON]?
    var textures: [Texture]?
    var images: [Image]?

    struct Scene: Decodable { var nodes: [Int]? }
    struct Node: Decodable {
        var mesh: Int?
        var children: [Int]?
        var matrix: [Float]?
        var translation: [Float]?
        var rotation: [Float]?
        var scale: [Float]?

        var localTransform: simd_float4x4 {
            if let m = matrix, m.count == 16 {
                return simd_float4x4(columns: (
                    [m[0], m[1], m[2], m[3]], [m[4], m[5], m[6], m[7]],
                    [m[8], m[9], m[10], m[11]], [m[12], m[13], m[14], m[15]]
                ))
            }
            let t = translation.flatMap { $0.count == 3 ? SIMD3<Float>($0[0], $0[1], $0[2]) : nil } ?? .zero
            let r = rotation.flatMap { $0.count == 4 ? simd_quatf(ix: $0[0], iy: $0[1], iz: $0[2], r: $0[3]) : nil }
                ?? simd_quatf(angle: 0, axis: [0, 1, 0])
            let s = scale.flatMap { $0.count == 3 ? SIMD3<Float>($0[0], $0[1], $0[2]) : nil } ?? .one
            return Transform(scale: s, rotation: r, translation: t).matrix
        }
    }
    struct MeshJSON: Decodable { var primitives: [Primitive] }
    struct Primitive: Decodable {
        var attributes: [String: Int]
        var indices: Int?
        var material: Int?
        var mode: Int?
    }
    struct Accessor: Decodable {
        var bufferView: Int?
        var byteOffset: Int?
        var componentType: Int
        var count: Int
        var normalized: Bool?
    }
    struct BufferView: Decodable {
        var buffer: Int
        var byteOffset: Int?
        var byteLength: Int
        var byteStride: Int?
    }
    struct MaterialJSON: Decodable { var pbrMetallicRoughness: PBR? }
    struct PBR: Decodable {
        var baseColorFactor: [Float]?
        var baseColorTexture: TextureRef?
        var metallicFactor: Float?
        var roughnessFactor: Float?
    }
    struct TextureRef: Decodable { var index: Int }
    struct Texture: Decodable { var source: Int? }
    struct Image: Decodable { var bufferView: Int?; var mimeType: String? }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
