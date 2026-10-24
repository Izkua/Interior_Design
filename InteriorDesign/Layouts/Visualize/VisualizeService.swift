import Foundation
import UIKit

/// The look of the AI picture.
enum VisualStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case modern, scandinavian, warm, minimal

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// What gets sent to make a picture: the room's shape, where each piece
/// goes, the style, and optionally a photo of the real room.
struct VisualizeRequest: Encodable, Sendable {
    struct Piece: Encodable, Sendable {
        var name: String
        var type: String
        var widthCm: Double
        var depthCm: Double
        var heightCm: Double
        var x: Double
        var y: Double
        var rotation: Int
    }
    var style: VisualStyle
    var corners: [Point2D]
    var features: [FixedFeature]
    var pieces: [Piece]
    /// Base64 JPEG, at most 1024 px on its long side.
    var roomPhoto: String?

    init(room: Room, placements: [ItemPlacement], items: [LayoutItem], style: VisualStyle, roomPhoto: UIImage?) {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        self.style = style
        corners = room.corners
        features = room.features
        pieces = placements.compactMap { p in
            byID[p.itemID].map {
                Piece(name: $0.name, type: $0.type.rawValue, widthCm: $0.width, depthCm: $0.depth, heightCm: $0.height,
                      x: p.x, y: p.y, rotation: p.rotation)
            }
        }
        self.roomPhoto = roomPhoto
            .flatMap { $0.jpegData(compressionQuality: 0.9) }
            .flatMap { PhotoResizer.jpeg(from: $0, maxSide: 1024, quality: 0.7) }?
            .base64EncodedString()
    }
}

enum VisualizeError: LocalizedError, Equatable {
    case notAvailable
    case signInNeeded
    /// Daily or monthly limit, or the monthly budget; the message says which.
    case limitReached(String)
    case rejected(String)
    case timedOut
    case offline
    case failed

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "AI pictures aren't available yet."
        case .signInNeeded: return "Sign in to make AI pictures."
        case .limitReached(let message): return message
        case .rejected(let message): return message.isEmpty ? "That picture couldn't be made. Try a different style or room photo." : message
        case .timedOut: return "That took too long. Try again; it didn't count toward your limit."
        case .offline: return "You're offline. Try again when you're connected; nothing was used up."
        case .failed: return "Something went wrong. Nothing was used up; please try again."
        }
    }
}

protocol VisualizeService: Sendable {
    func generate(_ request: VisualizeRequest) async throws -> UIImage
}

/// Asks the generate-image Edge Function. The backend checks sign-in,
/// limits, and budget, and only counts a picture once it succeeds.
struct BackendVisualizeService: VisualizeService {
    var accessToken: @Sendable () async -> String?

    func generate(_ body: VisualizeRequest) async throws -> UIImage {
        guard BackendConfig.visualizeEnabled else { throw VisualizeError.notAvailable }
        guard let token = await accessToken() else { throw VisualizeError.signInNeeded }

        var request = URLRequest(url: BackendConfig.functionsURL.appendingPathComponent("generate-image"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90   // image models can be slow
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw VisualizeError.timedOut
        } catch {
            throw VisualizeError.offline
        }
        struct Reply: Decodable { var image: String?; var error: String? }
        let reply = try? JSONDecoder().decode(Reply.self, from: data)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200:
            guard let base64 = reply?.image, let bytes = Data(base64Encoded: base64), let image = UIImage(data: bytes) else {
                throw VisualizeError.failed
            }
            return image
        case 401: throw VisualizeError.signInNeeded
        case 429, 503: throw VisualizeError.limitReached(reply?.error ?? "You've reached the limit for now.")
        case 422: throw VisualizeError.rejected(reply?.error ?? "")
        case 501: throw VisualizeError.notAvailable
        case 504: throw VisualizeError.timedOut
        default: throw VisualizeError.failed
        }
    }
}

#if DEBUG
/// A stand-in picture for trying the screens without a paid model. Debug
/// builds only; it's plainly labeled "Demo".
struct DemoVisualizeService: VisualizeService {
    func generate(_ request: VisualizeRequest) async throws -> UIImage {
        try await Task.sleep(for: .seconds(1.5))
        let size = CGSize(width: 1024, height: 768)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors: [UIColor] = switch request.style {
            case .modern: [UIColor(hex: 0xD9DDE0), UIColor(hex: 0x6E7A82)]
            case .scandinavian: [UIColor(hex: 0xF4F1EA), UIColor(hex: 0xC9B79C)]
            case .warm: [UIColor(hex: 0xF3D9C0), UIColor(hex: 0xA8643C)]
            case .minimal: [UIColor(hex: 0xFFFFFF), UIColor(hex: 0xBDBDBD)]
            }
            let gradient = CGGradient(colorsSpace: nil, colors: colors.map(\.cgColor) as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            let text = "Demo picture\n\(request.style.title) · \(request.pieces.count) pieces"
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            (text as NSString).draw(
                in: CGRect(x: 0, y: size.height / 2 - 60, width: size.width, height: 140),
                withAttributes: [.font: UIFont.systemFont(ofSize: 54, weight: .semibold), .foregroundColor: UIColor.black.withAlphaComponent(0.6), .paragraphStyle: style]
            )
        }
    }
}
#endif

/// Adds the required notice to the bottom of a picture, so it stays on the
/// image when saved or shared, not just in the app.
enum AIImageLabel {
    static let text = "AI-generated inspiration; furniture and placement may differ."

    static func stamped(_ image: UIImage) -> UIImage {
        let size = image.size
        let band = max(size.height * 0.07, 36)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(at: .zero)
            UIColor.black.withAlphaComponent(0.55).setFill()
            UIRectFill(CGRect(x: 0, y: size.height - band, width: size.width, height: band))
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let font = UIFont.systemFont(ofSize: band * 0.4, weight: .medium)
            (text as NSString).draw(
                in: CGRect(x: 8, y: size.height - band + (band - font.lineHeight) / 2, width: size.width - 16, height: band),
                withAttributes: [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: style]
            )
        }
    }
}
