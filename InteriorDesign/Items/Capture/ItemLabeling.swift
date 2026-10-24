import Foundation
import UIKit
import Vision

/// What a photo seems to show.
struct ItemLabel: Equatable, Sendable {
    var type: ItemType
    /// 0 to 1: how sure the labeler is.
    var confidence: Double
    /// The labeler's own word for it, like "couch".
    var rawLabel: String

    /// Plain words for the person.
    var confidenceNote: String {
        switch confidence {
        case 0.6...: return "We're fairly sure this is a \(type.displayName.lowercased())."
        case 0.3..<0.6: return "This looks like a \(type.displayName.lowercased()), but check the type."
        default: return "We're not sure what this is. Pick the right type below."
        }
    }
}

/// Anything that can label a furniture photo. On-device Vision now; a
/// model on our backend can be swapped in later without touching screens.
protocol LabelingService: Sendable {
    func label(_ image: UIImage) async throws -> ItemLabel?
}

// MARK: - On the phone (free, offline)

/// Uses Apple's built-in image classifier. Free, private (the photo never
/// leaves the phone), and works offline, but its labels are broad.
struct VisionLabelingService: LabelingService {
    func label(_ image: UIImage) async throws -> ItemLabel? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try handler.perform([request])
            let observations = (request.results ?? []).map { ($0.identifier, Double($0.confidence)) }
            return LabelMapper.label(from: observations)
        }.value
    }
}

/// Turns the classifier's labels (it knows over a thousand things, from
/// "couch" to "banana") into our item types.
enum LabelMapper {
    /// Words that point to each type. Matched against whole words of the
    /// label, so "table" does not match "vegetable".
    static let keywords: [(ItemType, [String])] = [
        (.sofa, ["sofa", "couch", "loveseat", "sectional", "futon", "settee"]),
        (.bed, ["bed", "bunk bed", "mattress", "headboard", "bedroom"]),
        (.desk, ["desk", "writing desk", "office desk"]),
        (.tvStand, ["tv stand", "entertainment center", "media console", "television", "tv"]),
        (.dresser, ["dresser", "chest of drawers", "wardrobe", "armoire", "cabinet", "sideboard", "drawer"]),
        (.shelf, ["bookshelf", "bookcase", "shelf", "shelving", "shelves"]),
        (.lamp, ["lamp", "floor lamp", "table lamp", "lampshade", "lamp shade"]),
        (.rug, ["rug", "carpet", "area rug", "mat"]),
        (.chair, ["chair", "armchair", "stool", "office chair", "rocking chair", "recliner", "bench"]),
        (.table, ["table", "coffee table", "dining table", "side table", "nightstand", "end table"]),
    ]

    /// The most likely item type, adding up evidence across labels.
    /// Labels below 5% are ignored as noise.
    static func label(from observations: [(identifier: String, confidence: Double)]) -> ItemLabel? {
        var best: [ItemType: (score: Double, raw: String)] = [:]
        for (identifier, confidence) in observations where confidence >= 0.05 {
            let text = " " + identifier.lowercased().replacingOccurrences(of: "_", with: " ") + " "
            for (type, words) in keywords where words.contains(where: { text.contains(" \($0) ") }) {
                let previous = best[type]
                // Combine evidence: two 50% labels make 75%, not 100%.
                let combined = 1 - (1 - (previous?.score ?? 0)) * (1 - confidence)
                best[type] = (combined, previous?.raw ?? identifier)
                break
            }
        }
        guard let top = best.max(by: { $0.value.score < $1.value.score }) else { return nil }
        return ItemLabel(type: top.key, confidence: top.value.score, rawLabel: top.value.raw)
    }
}

// MARK: - On our backend (later, off for now)

/// Sends the photo to the label-item Edge Function, which can use a more
/// accurate (paid) vision model. Off until a model is chosen; see
/// `BackendConfig.backendLabelingEnabled`.
struct BackendLabelingService: LabelingService {
    var accessToken: @Sendable () async -> String?

    func label(_ image: UIImage) async throws -> ItemLabel? {
        guard let token = await accessToken(),
              let jpeg = image.jpegData(compressionQuality: 0.7) else { return nil }
        var request = URLRequest(url: BackendConfig.functionsURL.appendingPathComponent("label-item"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["image": jpeg.base64EncodedString()])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        struct Reply: Decodable { var type: String; var confidence: Double; var label: String }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard let type = ItemType(rawValue: reply.type) else { return nil }
        return ItemLabel(type: type, confidence: reply.confidence, rawLabel: reply.label)
    }
}

/// The labeler to use: the backend one when switched on and signed in,
/// otherwise Vision. If the backend fails, Vision answers instead.
struct PreferredLabelingService: LabelingService {
    func label(_ image: UIImage) async throws -> ItemLabel? {
        if BackendConfig.backendLabelingEnabled, await AuthStore.shared.isSignedIn,
           let label = try? await BackendLabelingService(accessToken: { await AuthStore.shared.validAccessToken() }).label(image) {
            return label
        }
        return try await VisionLabelingService().label(image)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
