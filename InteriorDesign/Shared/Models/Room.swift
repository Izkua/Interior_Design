import Foundation
import SwiftData

enum RoomShape: String, Codable, CaseIterable, Identifiable {
    case rectangle
    case square
    /// Any outline drawn corner by corner in the advanced builder.
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .square: return "Square"
        case .custom: return "Custom"
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

/// A wall length the person measured with a tape, as opposed to the
/// length the drawing happens to have.
struct WallMeasurement: Codable, Hashable {
    var wall: Int
    var lengthCm: Double
}

/// Everything the advanced builder edits, in one value, so a whole edit
/// can be saved for undo and put back in one step.
struct RoomOutline: Equatable {
    var corners: [Point2D]
    var features: [FixedFeature]
    var measurements: [WallMeasurement]
    var uncertainWalls: [Int] = []
}

@Model
final class Room {
    var uuid: UUID
    var name: String
    var shape: RoomShape
    /// Corner points in centimeters, clockwise from the top-left.
    var corners: [Point2D]
    var features: [FixedFeature]
    /// Walls the person measured. Rooms saved before this existed load
    /// with none.
    var measurements: [WallMeasurement] = []
    /// Walls a scan wasn't sure about, highlighted until the person
    /// measures or moves them.
    var uncertainWalls: [Int] = []
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
    var area: Double { PolygonGeometry.area(corners) }

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

    /// Switches between rectangle, square, and custom. Going to custom
    /// keeps the corners so they can be edited one by one; going back to a
    /// rectangle or square uses the room's overall width and length.
    func setShape(_ newShape: RoomShape) {
        let wasCustom = shape == .custom
        shape = newShape
        switch newShape {
        case .square:
            measurements = []
            uncertainWalls = []
            resize(width: width, length: width)
        case .rectangle:
            if wasCustom {
                measurements = []
                uncertainWalls = []
                resize(width: width, length: length)
            } else {
                updatedAt = Date()
            }
        case .custom:
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

    // MARK: Corners (advanced builder)

    /// Corners, features, measurements, and unsure walls together, for undo.
    var outline: RoomOutline {
        get { RoomOutline(corners: corners, features: features, measurements: measurements, uncertainWalls: uncertainWalls) }
        set {
            corners = newValue.corners
            features = newValue.features
            measurements = newValue.measurements
            uncertainWalls = newValue.uncertainWalls
            updatedAt = Date()
        }
    }

    /// Moves every door, window, and outlet fully onto its wall.
    func refitFeatures() {
        features = features.map(fitted)
    }

    /// Moves one corner. Doors and windows on the two walls that meet there
    /// slide with their walls.
    func moveCorner(_ index: Int, to point: Point2D) {
        guard corners.indices.contains(index) else { return }
        let old = corners
        corners[index] = point
        features = features.map { stretched($0, from: old) }
        // Moving a corner by hand counts as checking the two walls at it.
        let before = PolygonGeometry.wrap(index - 1, corners.count)
        uncertainWalls.removeAll { $0 == index || $0 == before }
        updatedAt = Date()
    }

    /// Adds a corner at `point`, splitting the wall nearest to it. Returns
    /// the new corner's index.
    @discardableResult
    func insertCorner(at point: Point2D) -> Int {
        let old = corners
        let wall = PlanGeometry.nearestWall(to: point, corners: old).wall
        let index = wall + 1
        corners.insert(point, at: index)
        features = features.map { replaced($0, from: old) }
        // The split wall is now two new walls, so its measurement no longer
        // applies; walls after it move up by one.
        measurements = measurements.compactMap { m in
            if m.wall == wall { return nil }
            return WallMeasurement(wall: m.wall > wall ? m.wall + 1 : m.wall, lengthCm: m.lengthCm)
        }
        // A split unsure wall leaves two unsure walls.
        uncertainWalls = uncertainWalls.flatMap { w -> [Int] in
            if w == wall { return [w, w + 1] }
            return [w > wall ? w + 1 : w]
        }
        updatedAt = Date()
        return index
    }

    /// Removes a corner, joining its two walls into one. A room keeps at
    /// least three corners, so this does nothing on a triangle.
    @discardableResult
    func removeCorner(_ index: Int) -> Bool {
        let count = corners.count
        guard count > 3, corners.indices.contains(index) else { return false }
        let old = corners
        corners.remove(at: index)
        // Features on either joined wall move to the nearest remaining wall.
        features = features.map { replaced($0, from: old) }
        let before = PolygonGeometry.wrap(index - 1, count)
        measurements = measurements.compactMap { m in
            if m.wall == before || m.wall == index { return nil }
            return WallMeasurement(wall: m.wall > index ? m.wall - 1 : m.wall, lengthCm: m.lengthCm)
        }
        // The two joined walls become one wall, at index `before` (shifted
        // down if it came after the removed corner).
        let joined = before > index ? before - 1 : before
        let joinedUnsure = uncertainWalls.contains(before) || uncertainWalls.contains(index)
        uncertainWalls = uncertainWalls.compactMap { w in
            if w == before || w == index { return nil }
            return w > index ? w - 1 : w
        } + (joinedUnsure ? [joined] : [])
        updatedAt = Date()
        return true
    }

    /// The length the person measured for a wall, if any.
    func measuredLength(_ wall: Int) -> Double? {
        measurements.first { $0.wall == wall }?.lengthCm
    }

    /// Records a measured wall length and moves the wall's far corner so
    /// the drawing matches it.
    func setWallLength(_ wall: Int, to length: Double) {
        guard corners.indices.contains(wall), length > 0 else { return }
        let old = corners
        corners = PolygonGeometry.settingWallLength(wall, to: length, corners: old)
        features = features.map { stretched($0, from: old) }
        recordMeasurement(wall, length)
        uncertainWalls.removeAll { $0 == wall }
        updatedAt = Date()
    }

    /// Each wall's measured length, or its drawn length if not measured.
    var lengthsForCheck: [Double] {
        corners.indices.map { measuredLength($0) ?? PlanGeometry.wallLength($0, corners: corners) }
    }

    /// Nil when the measured walls fit together (or nothing is measured);
    /// otherwise which wall is most likely off and by how much.
    var closureCheck: PolygonGeometry.ClosureCheck? {
        guard shape == .custom, !measurements.isEmpty else { return nil }
        return PolygonGeometry.closureCheck(corners: corners, lengths: lengthsForCheck)
    }

    /// Takes the suggested length for the wall that is off, then reshapes
    /// the room to match every measurement.
    func applyFix(_ check: PolygonGeometry.ClosureCheck) {
        recordMeasurement(check.wall, check.suggestedLength)
        fitToMeasurements()
    }

    /// Redraws the outline from the measured lengths, keeping each wall's
    /// direction and closing any small leftover gap.
    func fitToMeasurements() {
        let old = corners
        // Closing the gap tilts the walls a little, which changes the walk,
        // so repeat a few times until the measurements fit.
        for _ in 0..<20 {
            corners = PolygonGeometry.closedOutline(corners: corners, lengths: lengthsForCheck)
            if PolygonGeometry.closureCheck(corners: corners, lengths: lengthsForCheck, tolerance: 0.5) == nil {
                break
            }
        }
        features = features.map { stretched($0, from: old) }
        updatedAt = Date()
    }

    private func recordMeasurement(_ wall: Int, _ length: Double) {
        measurements.removeAll { $0.wall == wall }
        measurements.append(WallMeasurement(wall: wall, lengthCm: length))
        measurements.sort { $0.wall < $1.wall }
    }

    /// The feature on the same wall, the same fraction of the way along,
    /// after that wall changed length. For edits that keep the corner count.
    private func stretched(_ feature: FixedFeature, from old: [Point2D]) -> FixedFeature {
        let oldLength = PlanGeometry.wallLength(feature.wall, corners: old)
        let newLength = PlanGeometry.wallLength(feature.wall, corners: corners)
        var adjusted = feature
        if oldLength > 0 {
            adjusted.offsetCm = feature.offsetCm / oldLength * newLength
        }
        return fitted(adjusted)
    }

    /// The feature on whichever new wall passes closest to where it was.
    /// For edits that add or remove corners, which renumber the walls.
    private func replaced(_ feature: FixedFeature, from old: [Point2D]) -> FixedFeature {
        let spot = PlanGeometry.point(onWall: feature.wall, offset: feature.offsetCm, corners: old)
        let target = PlanGeometry.nearestWall(to: spot, corners: corners)
        var adjusted = feature
        adjusted.wall = target.wall
        adjusted.offsetCm = target.offset
        return fitted(adjusted)
    }
}
