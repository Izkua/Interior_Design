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
    static func straightening(_ points: [SIMD3<Float>]) -> simd_quatf {
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
        var best = search(around: .zero, step: 6, reach: 42, tilt: true)
        best = search(around: best, step: 1.5, reach: 6, tilt: true)
        best = search(around: best, step: 0.5, reach: 1.5, tilt: true)
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
