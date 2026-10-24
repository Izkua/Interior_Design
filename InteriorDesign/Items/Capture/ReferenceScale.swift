import Foundation
import CoreGraphics

/// Something of known size the person can point at in a photo, so the app
/// can work out how big everything else in the photo is.
enum ReferenceObject: String, CaseIterable, Identifiable {
    case creditCard
    case letterPaper
    case a4Paper
    case doorHeight
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .creditCard: return "Credit card (long side)"
        case .letterPaper: return "US letter paper (long side)"
        case .a4Paper: return "A4 paper (long side)"
        case .doorHeight: return "Standard door (height)"
        case .custom: return "Something I measured"
        }
    }

    /// Its real length in centimeters. Nil for a custom one.
    var lengthCm: Double? {
        switch self {
        case .creditCard: return 8.56     // ISO/IEC 7810 ID-1 card
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
