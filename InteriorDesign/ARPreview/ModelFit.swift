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
