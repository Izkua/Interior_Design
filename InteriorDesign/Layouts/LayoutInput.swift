import Foundation
import SwiftData

/// Turns the saved room and its items into the plain values the layout
/// engine works on, and saves the person's choice back.
extension Room {
    /// The layout the person picked, if any.
    var chosenLayout: RoomLayout? {
        layouts.first { $0.isChosen }
    }

    var layoutRoom: LayoutRoom {
        LayoutRoom(corners: corners, features: features)
    }

    /// The room's items, each with its spot in the chosen layout.
    var layoutItems: [LayoutItem] {
        let current = Dictionary((chosenLayout?.placements ?? []).map { ($0.itemID, $0) }, uniquingKeysWith: { a, _ in a })
        return items
            .sorted { $0.createdAt < $1.createdAt }
            .map { item in
                LayoutItem(
                    id: item.uuid,
                    type: item.type,
                    name: item.name,
                    width: item.widthCm,
                    depth: item.depthCm,
                    height: item.heightCm,
                    isFixed: item.isFixed,
                    current: current[item.uuid]
                )
            }
    }

    /// Changes whenever anything the engine looks at changes, so the
    /// screen knows when to work out new suggestions.
    var layoutSignature: String {
        let shape = corners.map { "\(Int($0.x)),\(Int($0.y))" }.joined(separator: ";")
        let doors = features.map { "\($0.kind.rawValue)\($0.wall):\(Int($0.offsetCm)):\(Int($0.widthCm)):\($0.opensInward)" }.joined(separator: ";")
        let things = layoutItems.map { "\($0.id):\(Int($0.width))x\(Int($0.depth))x\(Int($0.height)):\($0.isFixed)" }.joined(separator: ";")
        let chosen = chosenLayout.map { "\($0.uuid)" } ?? "-"
        return [shape, doors, things, chosen].joined(separator: "|")
    }

    /// Saves placements as the room's chosen layout, replacing the old one.
    func choose(_ placements: [ItemPlacement], label: String, score: Double, context: ModelContext) {
        for old in layouts where old.isChosen {
            context.delete(old)
        }
        let layout = RoomLayout(label: label, score: score, placements: placements)
        layout.isChosen = true
        context.insert(layout)
        layout.room = self
        updatedAt = Date()
        try? context.save()
    }
}

/// What happens to each item in a suggested layout, compared with where it
/// is now.
enum ItemChange: Equatable {
    /// Already there (within 15 cm, same direction).
    case stays
    case moves
    /// No current spot yet, so it is simply placed.
    case placed
    /// Didn't fit anywhere.
    case leftOut

    static func of(_ item: LayoutItem, in placements: [ItemPlacement]) -> ItemChange {
        guard let new = placements.first(where: { $0.itemID == item.id }) else { return .leftOut }
        guard let now = item.current else { return .placed }
        let distance = hypot(new.x - now.x, new.y - now.y)
        return distance < 15 && new.rotation == now.rotation ? .stays : .moves
    }
}
