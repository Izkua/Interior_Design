import Foundation

/// The three kinds of things a person owns or shops for. Furniture stands
/// on the floor and goes in floor layouts; wall decor hangs on a wall;
/// small decor sits on top of furniture.
enum ItemCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case furniture
    case wallDecor
    case smallDecor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .furniture: return "Furniture"
        case .wallDecor: return "Wall decor"
        case .smallDecor: return "Small decor"
        }
    }

    var symbol: String {
        switch self {
        case .furniture: return "sofa"
        case .wallDecor: return "photo.on.rectangle"
        case .smallDecor: return "leaf"
        }
    }

    /// Words to search the catalog with when nothing more specific is asked.
    var searchWords: String {
        switch self {
        case .furniture: return "furniture"
        case .wallDecor: return "wall art decor"
        case .smallDecor: return "home decor accessories"
        }
    }

    /// The types in this category, in the order pickers show them.
    var types: [ItemType] { ItemType.allCases.filter { $0.category == self } }
}

extension ItemType {
    var category: ItemCategory {
        switch self {
        case .poster, .framedArt, .canvasArt, .mirror, .wallShelf, .wallClock, .otherWallDecor:
            return .wallDecor
        case .plant, .vase, .books, .tableLamp, .monitor, .deskStorage, .tableClock, .candle, .otherSmallDecor:
            return .smallDecor
        default:
            return .furniture
        }
    }

    /// How a piece of wall decor hangs on the Walls page.
    var decorKind: DecorKind? {
        switch self {
        case .poster: return .poster
        case .framedArt: return .frame
        case .canvasArt: return .canvas
        case .mirror: return .mirror
        case .wallShelf: return .shelf
        case .wallClock: return .clock
        case .otherWallDecor: return .other
        default: return nil
        }
    }

    /// Words to search the catalog with for this type.
    var searchWords: String {
        switch self {
        case .poster: return "poster print"
        case .framedArt: return "framed wall art"
        case .canvasArt: return "canvas wall art"
        case .mirror: return "wall mirror"
        case .wallShelf: return "floating wall shelf"
        case .wallClock: return "wall clock"
        case .plant: return "artificial plant in pot"
        case .vase: return "decorative vase"
        case .books: return "decorative books"
        case .tableLamp: return "table lamp"
        case .monitor: return "computer monitor"
        case .deskStorage: return "desk organizer"
        case .tableClock: return "desk clock"
        case .candle: return "candle holder"
        case .otherWallDecor: return "wall decor"
        case .otherSmallDecor: return "decorative accents"
        default: return displayName.lowercased()
        }
    }

    /// True for furniture with a top that small decor can stand on.
    var hasSurface: Bool {
        switch self {
        case .desk, .table, .dresser, .shelf, .tvStand: return true
        default: return false
        }
    }
}

extension DecorKind {
    /// The item type to save a piece as in Current Items.
    var itemType: ItemType {
        switch self {
        case .frame: return .framedArt
        case .poster: return .poster
        case .canvas: return .canvasArt
        case .mirror: return .mirror
        case .shelf: return .wallShelf
        case .clock: return .wallClock
        case .other: return .otherWallDecor
        case .tv: return .framedArt
        }
    }
}
