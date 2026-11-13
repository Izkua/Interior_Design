import Foundation
import simd

/// How to fit a 3D model to a piece's saved size. A LiDAR scan is already
/// true to size, but a model built from plain photos (or downloaded) can
/// come in at any scale and either way round, so it's shrunk or grown
/// evenly, never stretched, until it fits inside the saved width, depth
/// and height. Meters.
enum ModelFit {
    struct Result: Equatable {
        /// Same in every direction, so the piece keeps its proportions.
        var scale: Float
        /// Turn the model a quarter turn so its long side lines up with
        /// the saved width.
        var turned: Bool
    }

    /// `extents`: the model's own width, height, depth (x, y, z).
    /// `target`: the saved width, height, depth.
    static func fit(extents: simd_float3, target: simd_float3) -> Result {
        let e = simd_max(extents, simd_float3(repeating: 0.001))
        let t = simd_max(target, simd_float3(repeating: 0.001))
        // Which way round matches the saved footprint's shape better.
        let straight = abs(log(e.x / e.z) - log(t.x / t.z))
        let sideways = abs(log(e.z / e.x) - log(t.x / t.z))
        let turned = sideways + 0.05 < straight
        let footprint = turned ? simd_float2(e.z, e.x) : simd_float2(e.x, e.z)
        let scale = min(t.x / footprint.x, t.z / footprint.y, t.y / e.y)
        return Result(scale: scale, turned: turned)
    }
}

// MARK: - Straightening AI models

extension ModelFit {
    /// The turn that stands an AI-made model up straight and squares it to
    /// the axes. AI models are built as seen from the product photo's
    /// camera, so a photo taken from above at an angle gives a model that
    /// leans and sits at a slant. A piece of furniture standing straight,
    /// squared up, fits in the smallest box, so this tries small tilts
    /// (up to 30°, so a tall piece is never laid down) and turns, and keeps
    /// the one with the smallest box.
    static func straightening(_ points: [SIMD3<Float>], tilt allowTilt: Bool = true) -> simd_quatf {
        let sample = thinned(points, max: 1500)
        guard sample.count >= 4 else { return simd_quatf(angle: 0, axis: [0, 1, 0]) }

        func rotation(_ a: SIMD3<Float>) -> simd_quatf {
            // a = (tilt forward, turn, tilt sideways), in degrees.
            let r = Float.pi / 180
            return simd_quatf(angle: a.y * r, axis: [0, 1, 0])
                * simd_quatf(angle: a.z * r, axis: [0, 0, 1])
                * simd_quatf(angle: a.x * r, axis: [1, 0, 0])
        }
        func volume(_ a: SIMD3<Float>) -> Float {
            let m = simd_float3x3(rotation(a))
            var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
            for p in sample {
                let q = m * p
                lo = simd_min(lo, q)
                hi = simd_max(hi, q)
            }
            let e = hi - lo
            return e.x * e.y * e.z
        }
        func search(around center: SIMD3<Float>, step: Float, reach: Float, tilt: Bool) -> SIMD3<Float> {
            var best = center, bestVolume = volume(center)
            let n = Int(reach / step)
            for i in -n...n {
                for j in (tilt ? -n : 0)...(tilt ? n : 0) {
                    for k in (tilt ? -n : 0)...(tilt ? n : 0) {
                        var a = center + SIMD3(Float(j), Float(i), Float(k)) * step
                        a.x = max(-30, min(30, a.x))
                        a.z = max(-30, min(30, a.z))
                        let v = volume(a)
                        if v < bestVolume { best = a; bestVolume = v }
                    }
                }
            }
            return best
        }

        // Coarse, then finer, over turn and both tilts.
        var best = search(around: .zero, step: 6, reach: 42, tilt: allowTilt)
        best = search(around: best, step: 1.5, reach: 6, tilt: allowTilt)
        best = search(around: best, step: 0.5, reach: 1.5, tilt: allowTilt)
        // If leaning barely helps, the model was already standing straight:
        // only square it up.
        let level = search(around: SIMD3(0, best.y, 0), step: 0.5, reach: 3, tilt: false)
        if volume(best) > volume(level) * 0.97 { best = level }
        return rotation(best)
    }

    /// Fills the saved size exactly, stretching each direction on its own.
    /// For AI models, whose proportions are a guess while the catalog's
    /// sizes are measured. (Scans and imported models keep their shape.)
    static func stretch(extents: simd_float3, target: simd_float3) -> (scale: simd_float3, turned: Bool) {
        let e = simd_max(extents, simd_float3(repeating: 0.001))
        let turned = fit(extents: e, target: target).turned
        // When turned a quarter, the model's x runs along the saved depth.
        let scale = turned
            ? simd_float3(target.z / e.x, target.y / e.y, target.x / e.z)
            : target / e
        return (scale, turned)
    }

    private static func thinned(_ points: [SIMD3<Float>], max: Int) -> [SIMD3<Float>] {
        guard points.count > max else { return points }
        let step = Double(points.count) / Double(max)
        return (0..<max).map { points[Int(Double($0) * step)] }
    }
}

// MARK: - Sets (a table with its chairs, and so on)

extension ModelFit {
    /// True for products sold as a set, like "6 Pc Dinette Set" or "Dining
    /// table with 4 chairs". Retailers usually list only the table's size
    /// for these, so the whole model must not be squeezed into it.
    static func isSet(name: String) -> Bool {
        let patterns = [
            #"\bset\b"#, #"\bdinette\b"#, #"\bbistro\b"#,
            #"\b(with|and|&)\s+(\d+\s+)?(chairs|stools|bench)\b"#,
            #"\b\d+\s*-?\s*(pc|pcs|piece|pieces)\b"#,
        ]
        let text = name.lowercased()
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// How to place a set: turn it so the table is square to the outline,
    /// and size it so the table top matches the listed size. The chairs then
    /// come out at their natural size around it.
    struct SetPlacement: Equatable {
        init(turn: Float, scale: Float, scaleX: Float? = nil, scaleZ: Float? = nil, heightScale: Float? = nil, tableCenter: SIMD2<Float>) {
            self.turn = turn
            self.scale = scale
            self.scaleX = scaleX ?? scale
            self.scaleZ = scaleZ ?? scale
            self.heightScale = heightScale ?? scale
            self.tableCenter = tableCenter
        }

        /// Extra turn (radians, around up) to square the table.
        var turn: Float
        /// Across, on average.
        var scale: Float
        /// Along the width and the depth, so the table top matches.
        var scaleX: Float
        var scaleZ: Float
        /// Up, so the table top comes out at the listed height.
        var heightScale: Float
        /// Where the table top's middle is, after the turn (before scaling),
        /// so it can be moved onto the outline's middle.
        var tableCenter: SIMD2<Float>
    }

    /// Finds the table in a set model: the highest large flat surface
    /// facing up (chair seats are lower; chair backs don't face up). Nil if
    /// there isn't a clear one, and the usual sizing is used instead.
    /// `meshes`: corner points and triangles; `target`: listed width,
    /// height, depth in meters.
    static func setPlacement(meshes: [(positions: [SIMD3<Float>], indices: [UInt32])], target: SIMD3<Float>) -> SetPlacement? {
        // Upward-facing triangles: their height, size, and corners.
        var flats: [(y: Float, area: Float, corners: [SIMD3<Float>])] = []
        var lowest = Float.greatestFiniteMagnitude, highest = -Float.greatestFiniteMagnitude
        for mesh in meshes {
            for p in mesh.positions { lowest = min(lowest, p.y); highest = max(highest, p.y) }
            var i = 0
            while i + 2 < mesh.indices.count {
                let a = mesh.positions[Int(mesh.indices[i])], b = mesh.positions[Int(mesh.indices[i + 1])], c = mesh.positions[Int(mesh.indices[i + 2])]
                i += 3
                let n = simd_cross(b - a, c - a)
                let length = simd_length(n)
                guard length > 0, abs(n.y) / length > 0.9 else { continue }
                flats.append(((a.y + b.y + c.y) / 3, length / 2, [a, b, c]))
            }
        }
        let height = highest - lowest
        guard height > 0, !flats.isEmpty else { return nil }

        // Flat area by height, in 40 bands.
        let bands = 40
        func band(_ y: Float) -> Int { min(bands - 1, max(0, Int((y - lowest) / height * Float(bands)))) }
        var area = [Float](repeating: 0, count: bands)
        for f in flats { area[band(f.y)] += f.area }
        guard let biggest = area.max(), biggest > 0 else { return nil }
        // The highest band with plenty of flat area, above the bottom third
        // (so it isn't a rug or the feet).
        guard let top = (bands / 3..<bands).reversed().first(where: { area[$0] >= biggest * 0.35 }) else { return nil }
        // At that height there can also be bits of the chairs (the top rail
        // of a chair back). The table top is the biggest connected piece.
        let points = largestPatch(flats.filter { abs(band($0.y) - top) <= 1 }.map(\.corners))
        guard points.count >= 12 else { return nil }
        let tableTop = points.map(\.y).reduce(0, +) / Float(points.count) - lowest

        // Square the table top: the turn with the smallest box around it.
        func box(_ angle: Float) -> (size: SIMD2<Float>, center: SIMD2<Float>) {
            let c = cos(angle), s = sin(angle)
            var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
            for p in points {
                let q = SIMD2(c * p.x + s * p.z, -s * p.x + c * p.z)
                lo = simd_min(lo, q); hi = simd_max(hi, q)
            }
            return (hi - lo, (hi + lo) / 2)
        }
        var bestAngle: Float = 0, bestArea = Float.greatestFiniteMagnitude
        for step in -45...45 {
            let angle = Float(step) * .pi / 180
            let size = box(angle).size
            if size.x * size.y < bestArea { bestArea = size.x * size.y; bestAngle = angle }
        }
        var top2 = box(bestAngle)
        // Line the table's long side up with the listed long side.
        let wantWide = target.x >= target.z
        if (top2.size.x >= top2.size.y) != wantWide, abs(top2.size.x - top2.size.y) > 0.05 * max(top2.size.x, top2.size.y) {
            bestAngle += .pi / 2
            top2 = box(bestAngle)
        }
        guard top2.size.x > 0, top2.size.y > 0 else { return nil }
        // The table top matches the listed width and depth. If the AI got
        // the table's shape quite wrong, don't stretch more than 25% apart.
        let average = (target.x / top2.size.x + target.z / top2.size.y) / 2
        let scaleX = min(max(target.x / top2.size.x, average / 1.25), average * 1.25)
        let scaleZ = min(max(target.z / top2.size.y, average / 1.25), average * 1.25)
        let scale = average
        // AI models often make the table a bit low or high for its size.
        // Raise or lower it to the listed height, within reason.
        var heightScale = scale
        if tableTop > 0, target.y > 0 {
            heightScale = min(max(target.y / tableTop, scale * 0.75), scale * 1.33)
        }
        return SetPlacement(turn: bestAngle, scale: scale, scaleX: scaleX, scaleZ: scaleZ, heightScale: heightScale, tableCenter: top2.center)
    }
}

// MARK: - Leveling by flat surfaces

extension ModelFit {
    /// The tilt that makes the model's flat surfaces (a table top, a seat,
    /// a bed) level. A piece of furniture's biggest flat areas face up, so
    /// this tries tilts up to 30° and keeps the one where the most surface
    /// area faces straight up or down. More reliable than the smallest-box
    /// test for sets, where chairs around a table can make a tilted box
    /// look smaller. Nil if the model has no clear flat surfaces.
    static func leveling(_ meshes: [(positions: [SIMD3<Float>], indices: [UInt32])]) -> simd_quatf? {
        // Triangle facing directions and sizes (a sample, for speed).
        var faces: [(normal: SIMD3<Float>, area: Float)] = []
        var total: Float = 0
        for mesh in meshes {
            var i = 0
            while i + 2 < mesh.indices.count {
                let a = mesh.positions[Int(mesh.indices[i])], b = mesh.positions[Int(mesh.indices[i + 1])], c = mesh.positions[Int(mesh.indices[i + 2])]
                i += 3
                let n = simd_cross(b - a, c - a)
                let length = simd_length(n)
                guard length > 0 else { continue }
                total += length / 2
                // Only roughly horizontal ones can be the flat tops.
                if abs(n.y) / length > 0.6 { faces.append((n / length, length / 2)) }
            }
        }
        guard total > 0, !faces.isEmpty else { return nil }
        if faces.count > 5000 {
            let step = Double(faces.count) / 5000
            faces = (0..<5000).map { faces[Int(Double($0) * step)] }
        }
        let cone = cos(Float(6) * .pi / 180)
        func up(_ pitch: Float, _ roll: Float) -> SIMD3<Float> {
            let r = Float.pi / 180
            return simd_normalize(SIMD3(sin(roll * r), cos(pitch * r) * cos(roll * r), sin(pitch * r)))
        }
        func score(_ d: SIMD3<Float>) -> Float {
            faces.reduce(0) { $0 + (abs(simd_dot($1.normal, d)) >= cone ? $1.area : 0) }
        }
        var best = (pitch: Float(0), roll: Float(0), score: score(up(0, 0)))
        let level = best.score
        for pitch in stride(from: Float(-30), through: 30, by: 2) {
            for roll in stride(from: Float(-30), through: 30, by: 2) {
                let s = score(up(pitch, roll))
                if s > best.score { best = (pitch, roll, s) }
            }
        }
        for pitch in stride(from: best.pitch - 2, through: best.pitch + 2, by: 0.5) {
            for roll in stride(from: best.roll - 2, through: best.roll + 2, by: 0.5) {
                let s = score(up(pitch, roll))
                if s > best.score { best = (pitch, roll, s) }
            }
        }
        // Too little flat area to trust (a lamp, a plant).
        let sampled = faces.reduce(0) { $0 + $1.area }
        guard best.score > sampled * 0.15 else { return nil }
        // Already level, or close enough: don't tilt for a tiny gain.
        if best.score < level * 1.1 { return simd_quatf(angle: 0, axis: [0, 1, 0]) }
        return simd_quatf(from: up(best.pitch, best.roll), to: [0, 1, 0])
    }
}

extension ModelFit {
    /// The corners of the biggest connected flat piece among these
    /// triangles (each given by its three corners), judged on a grid seen
    /// from above.
    static func largestPatch(_ triangles: [[SIMD3<Float>]]) -> [SIMD3<Float>] {
        let all = triangles.flatMap { $0 }
        guard all.count >= 3 else { return all }
        var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for p in all { lo = simd_min(lo, SIMD2(p.x, p.z)); hi = simd_max(hi, SIMD2(p.x, p.z)) }
        let cells = 80
        let cell = max(hi.x - lo.x, hi.y - lo.y) / Float(cells - 1)
        guard cell > 0 else { return all }
        func key(_ p: SIMD3<Float>) -> Int {
            let x = min(cells - 1, max(0, Int((p.x - lo.x) / cell)))
            let z = min(cells - 1, max(0, Int((p.z - lo.y) / cell)))
            return z * cells + x
        }
        // Which triangles touch each cell (each triangle marks its corners
        // and middle).
        var occupied = [Int: [Int]]()
        for (t, tri) in triangles.enumerated() {
            let middle = (tri[0] + tri[1] + tri[2]) / 3
            for k in Set((tri + [middle]).map(key)) { occupied[k, default: []].append(t) }
        }
        // Group touching cells (including diagonal neighbors); keep the
        // group with the most flat area.
        var seen = Set<Int>()
        var best: (area: Float, triangles: Set<Int>) = (0, [])
        for start in occupied.keys where !seen.contains(start) {
            var stack = [start], group = Set<Int>()
            seen.insert(start)
            while let k = stack.popLast() {
                group.formUnion(occupied[k] ?? [])
                let x = k % cells, z = k / cells
                for dz in -1...1 {
                    for dx in -1...1 where dx != 0 || dz != 0 {
                        let nx = x + dx, nz = z + dz
                        guard nx >= 0, nz >= 0, nx < cells, nz < cells else { continue }
                        let n = nz * cells + nx
                        if occupied[n] != nil, seen.insert(n).inserted { stack.append(n) }
                    }
                }
            }
            let area = group.reduce(Float(0)) { sum, t in
                let tri = triangles[t]
                return sum + simd_length(simd_cross(tri[1] - tri[0], tri[2] - tri[0])) / 2
            }
            if area > best.area { best = (area, group) }
        }
        return best.triangles.flatMap { triangles[$0] }
    }
}
