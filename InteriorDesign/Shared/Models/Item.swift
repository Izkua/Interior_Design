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
    var source: ItemSource
    /// True for things that should not move, like a built-in wardrobe.
    var isFixed: Bool
    /// True while the size is a guess that the person has not confirmed.
    var isEstimated: Bool
    var notes: String
    var createdAt: Date
    var room: Room?

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
