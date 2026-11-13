import Foundation
import SwiftData

enum ItemType: String, Codable, CaseIterable, Identifiable {
    case sofa
    case bed
    case desk
    case table
    case chair
    case dresser
    case shelf
    case tvStand
    case lamp
    case rug
    case other
    // Wall decor: hangs on a wall (see `DecorKind`).
    case poster
    case framedArt
    case canvasArt
    case mirror
    case wallShelf
    case wallClock
    case otherWallDecor
    // Small decor: sits on a desk, table, dresser, or shelf.
    case plant
    case vase
    case books
    case tableLamp
    case monitor
    case deskStorage
    case tableClock
    case candle
    case otherSmallDecor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sofa: return "Sofa"
        case .bed: return "Bed"
        case .desk: return "Desk"
        case .table: return "Table"
        case .chair: return "Chair"
        case .dresser: return "Dresser"
        case .shelf: return "Shelf"
        case .tvStand: return "TV stand"
        case .lamp: return "Lamp"
        case .rug: return "Rug"
        case .other: return "Other"
        case .poster: return "Poster"
        case .framedArt: return "Framed art"
        case .canvasArt: return "Canvas art"
        case .mirror: return "Mirror"
        case .wallShelf: return "Wall shelf"
        case .wallClock: return "Wall clock"
        case .plant: return "Plant"
        case .vase: return "Vase"
        case .books: return "Books"
        case .tableLamp: return "Table lamp"
        case .monitor: return "Monitor"
        case .deskStorage: return "Desk storage"
        case .tableClock: return "Desk clock"
        case .candle: return "Candle"
        case .otherWallDecor, .otherSmallDecor: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .sofa: return "sofa"
        case .bed: return "bed.double"
        case .desk: return "desktopcomputer"
        case .table: return "table.furniture"
        case .chair: return "chair"
        case .dresser: return "cabinet"
        case .shelf: return "books.vertical"
        case .tvStand: return "tv"
        case .lamp: return "lamp.floor"
        case .rug: return "rectangle.dashed"
        case .other: return "cube"
        case .poster: return "doc.richtext"
        case .framedArt: return "photo"
        case .canvasArt: return "paintpalette"
        case .mirror: return "oval.portrait"
        case .wallShelf: return "books.vertical"
        case .wallClock: return "clock"
        case .plant: return "leaf"
        case .vase: return "camera.macro"
        case .books: return "book.closed"
        case .tableLamp: return "lamp.table"
        case .monitor: return "display"
        case .deskStorage: return "tray.2"
        case .tableClock: return "alarm"
        case .candle: return "flame"
        case .otherWallDecor: return "square.dashed"
        case .otherSmallDecor: return "cube"
        }
    }

    /// A realistic starting size in centimeters (width, depth, height).
    var defaultSize: (width: Double, depth: Double, height: Double) {
        switch self {
        case .sofa: return (200, 90, 85)
        case .bed: return (160, 200, 50)
        case .desk: return (140, 70, 75)
        case .table: return (140, 80, 75)
        case .chair: return (50, 50, 90)
        case .dresser: return (120, 45, 85)
        case .shelf: return (80, 30, 180)
        case .tvStand: return (150, 40, 50)
        case .lamp: return (30, 30, 150)
        case .rug: return (200, 140, 1)
        case .other: return (60, 60, 60)
        case .poster: return (50, 1, 70)
        case .framedArt: return (40, 3, 50)
        case .canvasArt: return (80, 4, 60)
        case .mirror: return (60, 3, 90)
        case .wallShelf: return (80, 20, 4)
        case .wallClock: return (35, 5, 35)
        case .plant: return (25, 25, 40)
        case .vase: return (15, 15, 30)
        case .books: return (25, 18, 22)
        case .tableLamp: return (25, 25, 50)
        case .monitor: return (62, 20, 45)
        case .deskStorage: return (30, 20, 15)
        case .tableClock: return (15, 8, 15)
        case .candle: return (10, 10, 12)
        case .otherWallDecor: return (40, 5, 40)
        case .otherSmallDecor: return (20, 20, 20)
        }
    }
}

enum ItemSource: String, Codable {
    case owned
    case catalog
}

@Model
final class Item {
    var uuid: UUID
    var type: ItemType
    var name: String
    /// Sizes in centimeters.
    var widthCm: Double
    var depthCm: Double
    var heightCm: Double
    @Attribute(.externalStorage) var photoData: Data?
    /// A 3D model of the piece: USDZ from a LiDAR scan or import, or GLB
    /// made by AI from its photo.
    @Attribute(.externalStorage) var modelData: Data? = nil
    /// The piece cut out of its photo (PNG), as the person chose it.
    @Attribute(.externalStorage) var cutoutData: Data? = nil
    /// Fingerprint of the photo the cutout was made from.
    var cutoutSource: String? = nil
    /// The piece's main color as "#RRGGBB|<photo size>", worked out on the
    /// phone from its photo and kept so it isn't redone every time.
    var colorKey: String? = nil
    /// For lamps: how warm or cool the bulb's light is (`LightWarmth`).
    /// Nil when unknown or not a lamp.
    var lightWarmthRaw: String? = nil
    var source: ItemSource
    /// True for things that should not move, like a built-in wardrobe.
    var isFixed: Bool
    /// True while the size is a guess that the person has not confirmed.
    var isEstimated: Bool
    var notes: String
    var createdAt: Date
    /// The item's main room. Items saved before multi-room support have only
    /// this, so it's kept as the first of the item's rooms.
    var room: Room?
    /// Any more rooms the item could go in, for furniture that moves around
    /// or hasn't found its place yet.
    var extraRooms: [Room] = []
    /// "Not sure yet": the item is a candidate for every room.
    var anyRoom: Bool = false

    init(
        type: ItemType,
        name: String? = nil,
        widthCm: Double? = nil,
        depthCm: Double? = nil,
        heightCm: Double? = nil,
        source: ItemSource = .owned,
        isFixed: Bool = false,
        isEstimated: Bool = false,
        notes: String = "",
        photoData: Data? = nil
    ) {
        let size = type.defaultSize
        self.uuid = UUID()
        self.type = type
        self.name = name ?? type.displayName
        self.widthCm = widthCm ?? size.width
        self.depthCm = depthCm ?? size.depth
        self.heightCm = heightCm ?? size.height
        self.source = source
        self.isFixed = isFixed
        self.isEstimated = isEstimated
        self.notes = notes
        self.photoData = photoData
        self.createdAt = Date()
    }
}

extension Item {
    /// For lamps: how warm or cool its light is. Nil when unknown.
    var lightWarmth: LightWarmth? {
        get { lightWarmthRaw.flatMap(LightWarmth.init(rawValue:)) }
        set { lightWarmthRaw = newValue?.rawValue }
    }
}

// MARK: - Rooms

extension Item {
    /// Every room the item is assigned to by name (not counting "any room").
    var assignedRooms: [Room] {
        var result: [Room] = []
        for candidate in [room].compactMap({ $0 }) + extraRooms where !result.contains(where: { $0.uuid == candidate.uuid }) {
            result.append(candidate)
        }
        return result
    }

    /// True if layouts for this room should include the item.
    func belongs(to target: Room) -> Bool {
        anyRoom || assignedRooms.contains { $0.uuid == target.uuid }
    }

    /// True when the item isn't in any room yet.
    var isUnassigned: Bool { !anyRoom && assignedRooms.isEmpty }

    /// Puts the item in these rooms: the first becomes its main room.
    func setRooms(_ rooms: [Room], anyRoom: Bool) {
        self.anyRoom = anyRoom
        room = rooms.first
        extraRooms = Array(rooms.dropFirst())
    }

    /// A short description for cards: "Living room", "2 rooms", "Any room".
    var roomSummary: String? {
        if anyRoom { return "Any room" }
        switch assignedRooms.count {
        case 0: return nil
        case 1: return assignedRooms[0].name
        default: return "\(assignedRooms.count) rooms"
        }
    }
}

extension Item {
    /// Other rooms whose saved layout already places this item, so the
    /// layout screen can say it can only be in one place at a time.
    func savedLayoutRooms(among rooms: [Room], excluding current: Room) -> [Room] {
        rooms.filter { other in
            other.uuid != current.uuid
                && (other.chosenLayout?.placements.contains { $0.itemID == uuid } ?? false)
        }
    }
}
