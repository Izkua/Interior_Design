import Foundation
import SwiftData

enum RoomShape: String, Codable, CaseIterable, Identifiable {
    case rectangle
    case square

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .square: return "Square"
        }
    }
}

enum FeatureKind: String, Codable, CaseIterable, Identifiable {
    case door
    case window
    case outlet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .door: return "Door"
        case .window: return "Window"
        case .outlet: return "Outlet"
        }
    }

    var symbol: String {
        switch self {
        case .door: return "door.left.hand.closed"
        case .window: return "square.split.2x2"
        case .outlet: return "bolt.fill"
        }
    }

    /// Width along the wall, in centimeters.
    var defaultWidthCm: Double {
        switch self {
        case .door: return 90
        case .window: return 120
        case .outlet: return 10
        }
    }
}

/// A door, window, or outlet fixed to a wall.
struct FixedFeature: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: FeatureKind
    /// Index of the wall it sits on (wall `i` runs from corner `i` to corner `i + 1`).
    var wall: Int
    /// Distance from the wall's first corner to the center of the feature, in cm.
    var offsetCm: Double
    var widthCm: Double
    /// Doors only: true when the hinge is at the end nearer the wall's
    /// first corner.
    var hingeAtStart: Bool = true
    /// Doors only: true when the door swings into the room. The swing area
    /// must stay clear of furniture.
    var opensInward: Bool = true

    init(kind: FeatureKind, wall: Int, offsetCm: Double, widthCm: Double, hingeAtStart: Bool = true, opensInward: Bool = true) {
        self.kind = kind
        self.wall = wall
        self.offsetCm = offsetCm
        self.widthCm = widthCm
        self.hingeAtStart = hingeAtStart
        self.opensInward = opensInward
    }

    // Decoded by hand so fields added later fall back to their defaults
    // instead of failing to load rooms saved by an older build.
    private enum CodingKeys: String, CodingKey {
        case id, kind, wall, offsetCm, widthCm, hingeAtStart, opensInward
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(FeatureKind.self, forKey: .kind)
        wall = try c.decode(Int.self, forKey: .wall)
        offsetCm = try c.decode(Double.self, forKey: .offsetCm)
        widthCm = try c.decode(Double.self, forKey: .widthCm)
        hingeAtStart = try c.decodeIfPresent(Bool.self, forKey: .hingeAtStart) ?? true
        opensInward = try c.decodeIfPresent(Bool.self, forKey: .opensInward) ?? true
    }
}

extension FeatureKind {
    /// Narrowest and widest a feature may be, in centimeters.
    var widthRange: ClosedRange<Double> {
        switch self {
        case .door: return 50...250
        case .window: return 30...600
        case .outlet: return 5...30
        }
    }

    /// Walls tried first when adding one: windows opposite the door,
    /// outlets on the side walls.
    var preferredWalls: [Int] {
        switch self {
        case .door: return [2, 3, 1, 0]
        case .window: return [0, 1, 3, 2]
        case .outlet: return [3, 1, 0, 2]
        }
    }
}

@Model
final class Room {
    var uuid: UUID
    var name: String
    var shape: RoomShape
    /// Corner points in centimeters, clockwise from the top-left.
    var corners: [Point2D]
    var features: [FixedFeature]
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Item.room)
    var items: [Item] = []

    @Relationship(deleteRule: .cascade, inverse: \RoomLayout.room)
    var layouts: [RoomLayout] = []

    @Relationship(deleteRule: .cascade, inverse: \Preferences.room)
    var preferences: Preferences?

    init(
        name: String,
        shape: RoomShape = .rectangle,
        width: Double,
        length: Double,
        features: [FixedFeature] = []
    ) {
        self.uuid = UUID()
        self.name = name
        self.shape = shape
        self.corners = PlanGeometry.rectangleCorners(
            width: width,
            length: shape == .square ? width : length
        )
        self.features = features
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: Size

    var width: Double {
        (corners.map(\.x).max() ?? 0) - (corners.map(\.x).min() ?? 0)
    }

    var length: Double {
        (corners.map(\.y).max() ?? 0) - (corners.map(\.y).min() ?? 0)
    }

    /// Floor area in square centimeters.
    var area: Double { width * length }

    /// Changes the room to a new rectangle and keeps every door, window,
    /// and outlet inside its wall.
    func resize(width newWidth: Double, length newLength: Double) {
        corners = PlanGeometry.rectangleCorners(width: newWidth, length: newLength)
        features = features.map(fitted)
        updatedAt = Date()
    }

    /// The feature moved and shrunk as needed so it sits fully on a wall
    /// of this room.
    private func fitted(_ feature: FixedFeature) -> FixedFeature {
        var adjusted = feature
        adjusted.wall = min(max(feature.wall, 0), max(corners.count - 1, 0))
        let wallLength = PlanGeometry.wallLength(adjusted.wall, corners: corners)
        adjusted.widthCm = min(feature.widthCm, wallLength)
        adjusted.offsetCm = PlanGeometry.clampOffset(
            feature.offsetCm,
            width: adjusted.widthCm,
            wallLength: wallLength
        )
        return adjusted
    }

    func setShape(_ newShape: RoomShape) {
        shape = newShape
        if newShape == .square {
            resize(width: width, length: width)
        } else {
            updatedAt = Date()
        }
    }

    func rename(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        name = trimmed
        updatedAt = Date()
    }

    // MARK: Fixed features

    /// Adds a door, window, or outlet on the emptiest part of a sensible
    /// wall, so it does not land on top of another one.
    @discardableResult
    func addFeature(_ kind: FeatureKind) -> FixedFeature {
        let spot = PlanGeometry.freeSpot(
            width: kind.defaultWidthCm,
            preferredWalls: kind.preferredWalls,
            corners: corners,
            taken: features.map { (wall: $0.wall, offset: $0.offsetCm, width: $0.widthCm) }
        )
        let feature = fitted(FixedFeature(
            kind: kind,
            wall: spot.wall,
            offsetCm: spot.offset,
            widthCm: kind.defaultWidthCm
        ))
        features.append(feature)
        updatedAt = Date()
        return feature
    }

    /// Changes one feature, then keeps it inside its wall.
    func updateFeature(id featureID: UUID, _ change: (inout FixedFeature) -> Void) {
        guard let index = features.firstIndex(where: { $0.id == featureID }) else { return }
        var feature = features[index]
        change(&feature)
        features[index] = fitted(feature)
        updatedAt = Date()
    }

    func removeFeature(id featureID: UUID) {
        features.removeAll { $0.id == featureID }
        updatedAt = Date()
    }
}
