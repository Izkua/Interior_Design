import Foundation
import SwiftData

/// Where one item sits in a layout.
struct ItemPlacement: Codable, Hashable {
    var itemID: UUID
    /// Center of the item, in room centimeters.
    var x: Double
    var y: Double
    /// 0, 90, 180, or 270 degrees.
    var rotation: Int
}

/// One arrangement of a room's items. (Named RoomLayout so it does not
/// clash with SwiftUI's `Layout` protocol.) The layout engine arrives in a
/// later week; this is the stored shape of its results.
@Model
final class RoomLayout {
    var uuid: UUID
    var label: String
    var score: Double
    var placements: [ItemPlacement]
    var createdAt: Date
    var room: Room?

    init(label: String, score: Double = 0, placements: [ItemPlacement] = []) {
        self.uuid = UUID()
        self.label = label
        self.score = score
        self.placements = placements
        self.createdAt = Date()
    }
}
