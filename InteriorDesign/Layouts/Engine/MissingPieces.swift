import Foundation

/// A piece the room seems to be missing, for the Catalog to fill later.
struct MissingPiece: Sendable, Hashable {
    var type: ItemType
    /// What to call it, like "Coffee table".
    var name: String
    /// Why it is suggested, in plain words.
    var reason: String
}

/// Simple rules for gaps, based on what is already in the room. Kept short
/// on purpose: a suggestion, never a requirement.
enum MissingPieces {
    /// `decor` is the wall and small decor types the room already has
    /// (hung or owned); leave it out to suggest furniture only.
    static func suggest(for items: [LayoutItem], decor: Set<ItemType>? = nil) -> [MissingPiece] {
        func has(_ type: ItemType) -> Bool { items.contains { $0.type == type } }
        let hasCoffeeTable = items.contains { $0.isCoffeeTable }
        let seats = items.filter { $0.type.isSeating }.count
        var result: [MissingPiece] = []

        if has(.sofa) || seats >= 2 {
            if !hasCoffeeTable {
                result.append(MissingPiece(type: .table, name: "Coffee table", reason: "Somewhere to put a drink within reach of the seats."))
            }
            if !has(.rug) {
                result.append(MissingPiece(type: .rug, name: "Rug", reason: "Ties the seating area together."))
            }
            if !has(.lamp) {
                result.append(MissingPiece(type: .lamp, name: "Floor lamp", reason: "Soft light beside the seats."))
            }
        }
        if has(.bed) {
            if !has(.dresser) {
                result.append(MissingPiece(type: .dresser, name: "Dresser", reason: "Storage for clothes."))
            }
            if !has(.lamp) {
                result.append(MissingPiece(type: .lamp, name: "Bedside lamp", reason: "Light for reading in bed."))
            }
        }
        if has(.desk), !items.contains(where: { $0.type == .chair }) {
            result.append(MissingPiece(type: .chair, name: "Desk chair", reason: "Something to sit on at the desk."))
        }
        if has(.tvStand), !has(.sofa), seats == 0 {
            result.append(MissingPiece(type: .sofa, name: "Sofa", reason: "Seating that faces the TV."))
        }
        if let decor, !items.isEmpty {
            let hasWallArt = decor.contains { $0.category == .wallDecor }
            if !hasWallArt, let anchor = items.first(where: { [.sofa, .bed, .desk, .dresser].contains($0.type) }) {
                result.append(MissingPiece(type: .framedArt, name: "Wall art", reason: "Something to look at above the \(anchor.type.displayName.lowercased())."))
            }
            if has(.desk), !decor.contains(.tableLamp) {
                result.append(MissingPiece(type: .tableLamp, name: "Desk lamp", reason: "Light to work by."))
            }
            if !decor.contains(.plant), items.count >= 2 {
                result.append(MissingPiece(type: .plant, name: "Plant", reason: "Brings a bit of life and color in."))
            }
        }
        // One lamp suggestion is enough.
        var seen = Set<ItemType>()
        return result.filter { $0.type != .lamp || seen.insert(.lamp).inserted }
    }
}
