import Foundation
import simd

/// A rough 3D stand-in for a piece of furniture, made of a few boxes: a
/// sofa is a seat, a back and two arms; a table is a top on four legs.
/// Kept apart from RealityKit so it can be tested.
///
/// Everything is in meters (what ARKit uses). The origin is the middle of
/// the piece's footprint on the floor; x runs along the width, y up, and
/// z along the depth with +z toward the front (the side you sit on or face).
/// Every part stays inside the true width × depth × height, so the whole
/// piece always takes up exactly the size that was saved.
enum FurnitureShape {
    /// Which of the piece's colors a part uses.
    enum Tone: Equatable {
        /// The main color (fabric, wood top).
        case main
        /// The second color (legs, frame, base).
        case accent
        /// Near-white, for pillows and lampshades.
        case light
    }

    struct Part: Equatable {
        /// Middle of the box.
        var center: simd_float3
        /// Full width, height, depth of the box.
        var size: simd_float3
        var tone: Tone
        /// Rounds the edges a little, so cushions look soft. Meters.
        var cornerRadius: Float = 0
    }

    /// The boxes for a piece of this type and size (in centimeters).
    static func parts(type: ItemType, widthCm: Double, depthCm: Double, heightCm: Double) -> [Part] {
        let w = Float(max(widthCm, 1) / 100)
        let d = Float(max(depthCm, 1) / 100)
        let h = Float(max(heightCm, 0.5) / 100)
        switch type {
        case .sofa: return sofa(w, d, h)
        case .chair: return chair(w, d, h)
        case .table, .desk: return table(w, d, h, desk: type == .desk)
        case .bed: return bed(w, d, h)
        case .dresser, .tvStand: return cabinet(w, d, h)
        case .shelf: return shelf(w, d, h)
        case .lamp: return lamp(w, d, h)
        case .rug: return [box(x: 0, y: 0, z: 0, w: w, h: min(h, 0.02), d: d, .main)]
        case .tableLamp: return lamp(w, d, h)
        default: return [box(x: 0, y: 0, z: 0, w: w, h: h, d: d, .main, radius: 0.01)]
        }
    }

    /// The smallest box that holds all the parts: (min corner, max corner).
    static func bounds(of parts: [Part]) -> (min: simd_float3, max: simd_float3) {
        var lo = simd_float3(repeating: .greatestFiniteMagnitude)
        var hi = simd_float3(repeating: -.greatestFiniteMagnitude)
        for part in parts {
            lo = simd_min(lo, part.center - part.size / 2)
            hi = simd_max(hi, part.center + part.size / 2)
        }
        return (lo, hi)
    }

    // MARK: Pieces

    private static func sofa(_ w: Float, _ d: Float, _ h: Float) -> [Part] {
        let arm = clamp(w * 0.1, 0.06, 0.2)
        let back = clamp(d * 0.22, 0.08, 0.3)
        let legH = min(0.08, h * 0.1)
        let seatH = h * 0.5 - legH           // seat top at about half the height
        let armH = h * 0.7 - legH
        var parts = legs(w: w, d: d, height: legH, thickness: 0.04, inset: 0.04)
        // Base under the cushions, running the full width.
        parts.append(box(x: 0, y: legH, z: 0, w: w, h: seatH * 0.55, d: d, .accent))
        // Seat cushion between the arms.
        parts.append(box(x: 0, y: legH + seatH * 0.55, z: back / 2, w: w - 2 * arm, h: seatH * 0.45, d: d - back, .main, radius: 0.03))
        // Back, full height.
        parts.append(box(x: 0, y: legH, z: -(d - back) / 2, w: w, h: h - legH, d: back, .main, radius: 0.04))
        // Arms.
        for side: Float in [-1, 1] {
            parts.append(box(x: side * (w - arm) / 2, y: legH, z: back / 2, w: arm, h: armH, d: d - back, .main, radius: 0.03))
        }
        return parts
    }

    private static func chair(_ w: Float, _ d: Float, _ h: Float) -> [Part] {
        let seatTop = min(0.47, h * 0.55)
        let seat: Float = 0.05
        let leg = clamp(min(w, d) * 0.08, 0.025, 0.05)
        let back = clamp(d * 0.12, 0.03, 0.1)
        var parts = legs(w: w, d: d, height: seatTop - seat, thickness: leg, inset: 0)
        parts.append(box(x: 0, y: seatTop - seat, z: 0, w: w, h: seat, d: d, .main, radius: 0.015))
        if h > seatTop + 0.05 {
            parts.append(box(x: 0, y: seatTop, z: -(d - back) / 2, w: w, h: h - seatTop, d: back, .main, radius: 0.015))
        }
        return parts
    }

    private static func table(_ w: Float, _ d: Float, _ h: Float, desk: Bool) -> [Part] {
        let top = clamp(h * 0.05, 0.02, 0.05)
        let leg = clamp(min(w, d) * 0.06, 0.03, 0.07)
        var parts = legs(w: w, d: d, height: h - top, thickness: leg, inset: 0.02)
        parts.append(box(x: 0, y: h - top, z: 0, w: w, h: top, d: d, .main, radius: 0.005))
        if desk, w > 0.8 {
            // A drawer unit hanging under one end of the top.
            let unitW = min(0.4, w * 0.3)
            let unitH = min(0.15, (h - top) * 0.25)
            parts.append(box(x: (w - unitW) / 2 - leg - 0.02, y: h - top - unitH, z: 0, w: unitW, h: unitH, d: d * 0.85, .main))
        }
        return parts
    }

    private static func bed(_ w: Float, _ d: Float, _ h: Float) -> [Part] {
        let frameH = h * 0.45
        // Pillows poke up to the full height; the mattress sits a little lower.
        let pillowH = min(0.1, (h - frameH) * 0.6)
        let mattressH = h - frameH - pillowH * 0.5
        let headboard = clamp(d * 0.04, 0.04, 0.1)
        var parts: [Part] = []
        parts.append(box(x: 0, y: 0, z: headboard / 2, w: w, h: frameH, d: d - headboard, .accent))
        parts.append(box(x: 0, y: frameH, z: headboard / 2, w: w * 0.97, h: mattressH, d: d - headboard, .main, radius: 0.03))
        // The headboard stays within the saved height, at the back.
        parts.append(box(x: 0, y: 0, z: -(d - headboard) / 2, w: w, h: h, d: headboard, .accent))
        // Pillows at the head end, half sunk into the mattress.
        let pillowD: Float = min(0.35, d * 0.18)
        let count: Float = w > 1.2 ? 2 : 1
        let pillowW = (w * 0.9) / count - 0.04
        for i in 0..<Int(count) {
            let x = count == 1 ? 0 : (i == 0 ? -1 : 1) * (pillowW / 2 + 0.02)
            parts.append(box(x: x, y: h - pillowH, z: -(d / 2) + headboard + pillowD / 2 + 0.03, w: pillowW, h: pillowH, d: pillowD, .light, radius: 0.04))
        }
        return parts
    }

    private static func cabinet(_ w: Float, _ d: Float, _ h: Float) -> [Part] {
        let legH = min(0.08, h * 0.12)
        var parts = legs(w: w, d: d, height: legH, thickness: 0.035, inset: 0.03)
        parts.append(box(x: 0, y: legH, z: 0, w: w, h: h - legH, d: d, .main, radius: 0.005))
        // Thin dark lines across the front, like drawer gaps.
        let rows = max(1, min(4, Int(((h - legH) / 0.25).rounded())))
        let gap: Float = 0.006
        for row in stride(from: 1, to: rows, by: 1) {
            let y = legH + (h - legH) * Float(row) / Float(rows) - gap / 2
            parts.append(box(x: 0, y: y, z: d / 2 - 0.0025, w: w * 0.96, h: gap, d: 0.005, .accent))
        }
        return parts
    }

    private static func shelf(_ w: Float, _ d: Float, _ h: Float) -> [Part] {
        let side = clamp(w * 0.03, 0.015, 0.03)
        let board: Float = 0.02
        var parts: [Part] = []
        for s: Float in [-1, 1] {
            parts.append(box(x: s * (w - side) / 2, y: 0, z: 0, w: side, h: h, d: d, .main))
        }
        parts.append(box(x: 0, y: 0, z: -(d - 0.01) / 2, w: w - 2 * side, h: h, d: 0.01, .accent))
        let count = max(2, Int((h / 0.35).rounded()) + 1)
        for i in 0..<count {
            let y = (h - board) * Float(i) / Float(count - 1)
            parts.append(box(x: 0, y: y, z: 0.005, w: w - 2 * side, h: board, d: d - 0.01, .main))
        }
        return parts
    }

    private static func lamp(_ w: Float, _ d: Float, _ h: Float) -> [Part] {
        let shadeH = clamp(h * 0.22, 0.12, 0.4)
        let base: Float = 0.03
        let pole: Float = 0.025
        return [
            box(x: 0, y: 0, z: 0, w: w * 0.7, h: base, d: d * 0.7, .accent, radius: 0.01),
            box(x: 0, y: base, z: 0, w: pole, h: h - base - shadeH * 0.5, d: pole, .accent),
            box(x: 0, y: h - shadeH, z: 0, w: w, h: shadeH, d: d, .light, radius: min(w, d) * 0.2),
        ]
    }

    // MARK: Helpers

    /// A box sitting with its bottom at `y`, centered on x and z.
    private static func box(x: Float, y: Float, z: Float, w: Float, h: Float, d: Float, _ tone: Tone, radius: Float = 0) -> Part {
        let size = simd_float3(max(w, 0.001), max(h, 0.001), max(d, 0.001))
        // A rounded corner can't be bigger than half the smallest side.
        let r = min(radius, size.min() / 2 * 0.9)
        return Part(center: simd_float3(x, y + size.y / 2, z), size: size, tone: tone, cornerRadius: max(r, 0))
    }

    /// Four legs at the corners of the footprint.
    private static func legs(w: Float, d: Float, height: Float, thickness: Float, inset: Float) -> [Part] {
        guard height > 0.005 else { return [] }
        let t = min(thickness, w / 4, d / 4)
        let x = w / 2 - inset - t / 2
        let z = d / 2 - inset - t / 2
        return [(-1, -1), (-1, 1), (1, -1), (1, 1)].map { (sx: Float, sz: Float) in
            box(x: sx * x, y: 0, z: sz * z, w: t, h: height, d: t, .accent)
        }
    }

    private static func clamp(_ value: Float, _ lo: Float, _ hi: Float) -> Float {
        min(max(value, lo), hi)
    }
}
