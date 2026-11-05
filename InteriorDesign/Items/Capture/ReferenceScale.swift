import Foundation
import CoreGraphics

/// Something of known size the person can point at in a photo, so the app
/// can work out how big everything else in the photo is.
enum ReferenceObject: String, CaseIterable, Identifiable {
    case walletCard
    case letterPaper
    case a4Paper
    case doorHeight
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walletCard: return "A standard-size card"
        case .letterPaper: return "US letter paper (long side)"
        case .a4Paper: return "A4 paper (long side)"
        case .doorHeight: return "Standard door (height)"
        case .custom: return "Something I measured"
        }
    }

    /// Its two sides in cm (long, short) for flat rectangles whose four
    /// corners can be tapped. Nil for a door or a custom length.
    var rectangleCm: (long: Double, short: Double)? {
        switch self {
        case .walletCard: return (8.56, 5.398)
        case .letterPaper: return (27.94, 21.59)
        case .a4Paper: return (29.7, 21.0)
        case .doorHeight, .custom: return nil
        }
    }

    /// Its real length in centimeters. Nil for a custom one.
    var lengthCm: Double? {
        switch self {
        case .walletCard: return 8.56     // ISO/IEC 7810 ID-1 card
        case .letterPaper: return 27.94   // 11 in
        case .a4Paper: return 29.7
        case .doorHeight: return 203.2    // 80 in, the usual US interior door
        case .custom: return nil
        }
    }
}

/// Converts distances in a photo to centimeters, from one reference of
/// known length.
///
/// This only works well when the reference and the furniture are about the
/// same distance from the camera and the photo is taken straight on;
/// otherwise the estimate can be off by 10% or more. That's why every size
/// from a photo stays "Estimated" until the person checks it.
struct ReferenceScale: Equatable {
    /// Centimeters per point in the photo.
    let cmPerPoint: Double

    /// Points closer than this are a mis-tap, not a measurement.
    static let minimumSpan: Double = 12

    /// Nil if the two taps are too close together to be meaningful.
    init?(referenceStart: CGPoint, referenceEnd: CGPoint, knownLengthCm: Double) {
        let span = Self.distance(referenceStart, referenceEnd)
        guard span >= Self.minimumSpan, knownLengthCm > 0 else { return nil }
        cmPerPoint = knownLengthCm / span
    }

    /// The real length between two points in the photo, in centimeters.
    func length(from a: CGPoint, to b: CGPoint) -> Double? {
        let span = Self.distance(a, b)
        guard span >= Self.minimumSpan else { return nil }
        return span * cmPerPoint
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(b.x - a.x, b.y - a.y))
    }
}

/// A perspective map from the photo onto the flat surface a card or sheet
/// of paper lies in, worked out from its four corners (a "homography").
///
/// Anything measured on that same surface comes out right even when the
/// photo is taken at an angle: with the card standing against the front of
/// a chair, its width and height; with the card lying on the floor, the
/// width and depth of the chair's footprint. Sizes off that surface can't be
/// measured from this photo.
struct PlaneScale {
    /// Maps photo points to the card's surface, in cm.
    private let h: [Double]
    /// True when the card looks strongly tilted in the photo, so the taps
    /// matter more and small errors grow. A straight-on retake helps.
    let looksAngled: Bool

    /// `corners`: the card's four corners in the photo, in order around it
    /// (either direction, starting anywhere). Nil for taps that are too
    /// close together or don't form a usable four-sided shape.
    init?(corners: [CGPoint], sizeCm: (long: Double, short: Double)) {
        guard corners.count == 4 else { return nil }
        let sides = (0..<4).map { ReferenceScale.distance(corners[$0], corners[($0 + 1) % 4]) }
        guard sides.allSatisfy({ $0 >= ReferenceScale.minimumSpan }) else { return nil }
        // The pair of opposite sides that looks longer is the long side.
        let firstIsLong = sides[0] + sides[2] >= sides[1] + sides[3]
        let a = firstIsLong ? sizeCm.long : sizeCm.short
        let b = firstIsLong ? sizeCm.short : sizeCm.long
        let plane = [CGPoint(x: 0, y: 0), CGPoint(x: a, y: 0), CGPoint(x: a, y: b), CGPoint(x: 0, y: b)]
        guard let h = Self.solve(from: corners, to: plane) else { return nil }
        self.h = h
        let mismatch = { (x: Double, y: Double) in abs(x - y) / max(x, y) }
        looksAngled = mismatch(sides[0], sides[2]) > 0.25 || mismatch(sides[1], sides[3]) > 0.25
    }

    /// A photo point on the card's surface, in cm.
    func planePoint(_ p: CGPoint) -> CGPoint? {
        let x = Double(p.x), y = Double(p.y)
        let w = h[6] * x + h[7] * y + 1
        guard abs(w) > 1e-9 else { return nil }
        return CGPoint(x: (h[0] * x + h[1] * y + h[2]) / w, y: (h[3] * x + h[4] * y + h[5]) / w)
    }

    /// The real distance between two photo points on the card's surface.
    func length(from a: CGPoint, to b: CGPoint) -> Double? {
        guard ReferenceScale.distance(a, b) >= ReferenceScale.minimumSpan,
              let pa = planePoint(a), let pb = planePoint(b) else { return nil }
        return ReferenceScale.distance(pa, pb)
    }

    /// The 8 numbers of the map from four point pairs (standard direct
    /// linear transform, solved by Gaussian elimination).
    static func solve(from src: [CGPoint], to dst: [CGPoint]) -> [Double]? {
        var m = [[Double]]()
        for i in 0..<4 {
            let x = Double(src[i].x), y = Double(src[i].y), u = Double(dst[i].x), v = Double(dst[i].y)
            m.append([x, y, 1, 0, 0, 0, -u * x, -u * y, u])
            m.append([0, 0, 0, x, y, 1, -v * x, -v * y, v])
        }
        for col in 0..<8 {
            guard let pivot = (col..<8).max(by: { abs(m[$0][col]) < abs(m[$1][col]) }), abs(m[pivot][col]) > 1e-9 else { return nil }
            m.swapAt(col, pivot)
            for row in 0..<8 where row != col {
                let factor = m[row][col] / m[col][col]
                if factor != 0 { for k in col...8 { m[row][k] -= factor * m[col][k] } }
            }
        }
        return (0..<8).map { m[$0][8] / m[$0][$0] }
    }
}

/// How the card was placed, which decides what the photo can measure.
enum CardPlacement: String, CaseIterable, Identifiable {
    /// Standing against the front of the item, facing the camera:
    /// measures width and height.
    case standing
    /// Lying flat on the floor next to the item: measures width and depth.
    case flat
    var id: String { rawValue }
    var title: String { self == .standing ? "Standing against the front" : "Lying flat on the floor" }
}
