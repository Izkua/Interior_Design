import Foundation
import UIKit

/// The one real measurement the person gives before scanning, so the draft
/// has a true scale (photos alone can't tell a small room from a big one).
struct KnownMeasurement: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// The wall the first photo faces.
        case firstWall
        /// A standard door, if they don't have a tape measure.
        case doorHeight
    }
    var kind: Kind
    var lengthCm: Double

    /// The fallback when nothing is measured: an 80 in (203 cm) door.
    static let standardDoor = KnownMeasurement(kind: .doorHeight, lengthCm: 203.2)
}

/// Turns room photos into a draft outline. Called after every photo with
/// all photos so far, so the draft improves step by step.
protocol ScanService: Sendable {
    func update(photos: [Data], known: KnownMeasurement, previous: RoomDraft?) async throws -> RoomDraft
}

enum ScanError: LocalizedError, Equatable {
    case notAvailable
    case signInNeeded
    case limitReached(String)
    case offline
    case unreadable

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "Room scan isn't available yet."
        case .signInNeeded: return "Sign in to use room scan."
        case .limitReached(let message): return message
        case .offline: return "You're offline. Your photos are kept; try again when you're back online."
        case .unreadable: return "We couldn't make sense of that photo. Try retaking it."
        }
    }
}

/// The scan loop's rules, kept apart from the screen so they can be tested.
enum ScanLoop {
    /// Never ask for more than this many photos.
    static let maxPhotos = 10

    /// True when the scan should stop: the outline is closed and every
    /// wall was seen, or the photo limit is reached.
    static func isFinished(draft: RoomDraft?, photoCount: Int) -> Bool {
        if photoCount >= maxPhotos { return true }
        return draft?.isComplete ?? false
    }

    /// Where to point the camera next. Before the model has an opinion,
    /// walk around the room one wall at a time.
    static func nextHint(draft: RoomDraft?, photoCount: Int) -> (direction: RoomDraft.Direction, text: String) {
        if isFinished(draft: draft, photoCount: photoCount) {
            return (.done, "That's enough photos. Let's check the outline.")
        }
        if let draft, let direction = draft.nextDirection, direction != .done {
            return (direction, draft.nextHint ?? "Turn \(direction.rawValue) and take the next photo.")
        }
        switch photoCount {
        case 0: return (.ahead, "Stand in a corner and photograph the wall you measured, floor to ceiling.")
        case 1, 2, 3: return (.right, "Turn right to the next wall and take a photo.")
        default: return (.right, "Turn to any wall that's still missing and take a photo.")
        }
    }

    /// Photos are shrunk before sending: smaller uploads, less cost, and
    /// enough detail for an outline.
    static func prepare(_ image: UIImage) -> Data? {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        return PhotoResizer.jpeg(from: data, maxSide: 1024, quality: 0.7)
    }
}

// MARK: - Backend

/// Sends photos to the scan-room Edge Function. Off until a vision model
/// is chosen (`BackendConfig.roomScanEnabled`).
struct BackendScanService: ScanService {
    var accessToken: @Sendable () async -> String?

    func update(photos: [Data], known: KnownMeasurement, previous: RoomDraft?) async throws -> RoomDraft {
        guard BackendConfig.roomScanEnabled else { throw ScanError.notAvailable }
        guard let token = await accessToken() else { throw ScanError.signInNeeded }

        var request = URLRequest(url: BackendConfig.functionsURL.appendingPathComponent("scan-room"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable {
            var photos: [String]
            var known: KnownMeasurement
            var previousCorners: [Point2D]?
        }
        request.httpBody = try JSONEncoder().encode(Body(
            photos: photos.map { $0.base64EncodedString() },
            known: known,
            previousCorners: previous?.corners
        ))

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ScanError.offline
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401: throw ScanError.signInNeeded
        case 429, 503:
            struct Message: Decodable { var error: String }
            throw ScanError.limitReached((try? JSONDecoder().decode(Message.self, from: data))?.error ?? "Try again later.")
        case 501: throw ScanError.notAvailable
        default: throw ScanError.unreadable
        }
        do {
            return try RoomDraftParser.parse(data)
        } catch {
            throw ScanError.unreadable
        }
    }
}

#if DEBUG
/// Pretends to scan, for trying the screens in the Simulator without a
/// paid model. Debug builds only; never ships. Each photo reveals one more
/// wall of a 420 × 360 cm room.
struct DemoScanService: ScanService {
    func update(photos: [Data], known: KnownMeasurement, previous: RoomDraft?) async throws -> RoomDraft {
        try await Task.sleep(for: .milliseconds(600))
        let seen = min(photos.count, 4)
        let json = """
        {"corners":[{"x":0,"y":0},{"x":420,"y":0},{"x":420,"y":360},{"x":0,"y":360}],
         "walls":[\((0..<4).map { i in i < seen ? #"{"seen":true,"confidence":\#(i == 1 ? 0.45 : 0.85)}"# : #"{"seen":false,"confidence":0}"# }.joined(separator: ","))],
         "features":[{"kind":"window","wall":0,"offsetCm":210,"widthCm":150,"confidence":0.8},
                     {"kind":"door","wall":2,"offsetCm":80,"widthCm":90,"confidence":0.7}],
         "closed":\(seen >= 4),
         "next":{"direction":"\(seen >= 4 ? "done" : "right")","hint":"Turn right to the next wall."}}
        """
        return try RoomDraftParser.parse(Data(json.utf8))
    }
}
#endif
