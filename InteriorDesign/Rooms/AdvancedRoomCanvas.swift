import SwiftUI

/// The advanced room builder's plan: a grid you draw the room on corner by
/// corner.
///
/// - Tap empty space to add a corner (it splits the nearest wall).
/// - Drag a corner to move it; with "Lock angles" on, its angles snap.
/// - Long-press a corner to delete it.
/// - Tap a wall to select it, so its measured length can be typed below.
/// - Drag a door, window, or outlet to slide it along the walls.
///
/// Wall lengths and corner angles update live while dragging.
struct AdvancedRoomCanvas: View {
    let room: Room
    @Binding var selectedWall: Int?
    @Binding var selectedFeatureID: UUID?
    let unit: UnitSystem
    let lockAngles: Bool
    /// Called once just before each change, so the screen can save the
    /// room's outline for undo.
    let willEdit: () -> Void

    /// What a touch started on.
    private enum Target: Equatable {
        case corner(Int)
        case feature(UUID)
        case wall(Int)
        case empty
    }

    @State private var target: Target?
    @State private var moved = false
    @State private var longPressFired = false
    @State private var longPressTask: Task<Void, Never>?
    @State private var activeCorner: Int?
    /// The scale and position are frozen while a finger is down, so the
    /// plan does not rescale under the finger as the room changes size.
    @State private var frozenSpace: CanvasSpace?
    @State private var deletedCount = 0

    /// How close a touch must be to count as hitting something, in points.
    private let cornerReach: CGFloat = 28
    private let featureReach: CGFloat = 30
    private let wallReach: CGFloat = 22

    var body: some View {
        // Reading these here makes the view redraw when they change.
        let corners = room.corners
        let features = room.features
        let selectedID = selectedFeatureID
        let wall = selectedWall
        let active = activeCorner
        let unsure = room.uncertainWalls
        let unit = self.unit

        GeometryReader { geo in
            let space = frozenSpace ?? CanvasSpace(corners: corners, size: geo.size, padding: 64)
            Canvas { context, size in
                AdvancedPlanPainter.paintGrid(&context, size: size, space: space, unit: unit)
                RoomPlanPainter.paint(
                    &context,
                    corners: corners,
                    features: features,
                    selectedID: selectedID,
                    space: space,
                    unit: unit
                )
                AdvancedPlanPainter.paintEditing(
                    &context,
                    corners: corners,
                    selectedWall: wall,
                    activeCorner: active,
                    uncertainWalls: unsure,
                    space: space
                )
            }
            .contentShape(Rectangle())
            .gesture(touchGesture(space: space))
        }
        .sensoryFeedback(.impact, trigger: deletedCount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Room outline with \(room.corners.count) corners")
        .accessibilityHint("Tap to add a corner. Drag a corner to move it. Long-press a corner to delete it.")
    }

    // MARK: Touch handling

    /// One gesture handles taps, long presses, and drags, so they never
    /// fight each other: what happens is decided by what the touch started
    /// on and whether the finger moved.
    private func touchGesture(space: CanvasSpace) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if target == nil {
                    begin(at: value.startLocation, space: space)
                }
                guard !longPressFired else { return }

                if !moved, hypot(value.translation.width, value.translation.height) > 6 {
                    moved = true
                    longPressTask?.cancel()
                    if case .corner = target { willEdit() }
                    if case .feature = target { willEdit() }
                }
                guard moved else { return }

                let point = (frozenSpace ?? space).roomPoint(value.location)
                switch target {
                case .corner(let index):
                    let landing = lockAngles
                        ? PolygonGeometry.snapCorner(index, to: point, corners: room.corners)
                        : point
                    room.moveCorner(index, to: landing)
                case .feature(let id):
                    slideFeature(id, to: point)
                default:
                    break
                }
            }
            .onEnded { value in
                longPressTask?.cancel()
                if !longPressFired && !moved {
                    tap(at: value.location, space: frozenSpace ?? space)
                }
                target = nil
                moved = false
                longPressFired = false
                activeCorner = nil
                frozenSpace = nil
            }
    }

    private func begin(at location: CGPoint, space: CanvasSpace) {
        frozenSpace = space
        target = hitTest(location, space: space)

        switch target {
        case .corner(let index):
            activeCorner = index
            // If the finger stays still for half a second, delete the corner.
            longPressTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, !moved, target == .corner(index) else { return }
                longPressFired = true
                activeCorner = nil
                if room.corners.count > 3 {
                    willEdit()
                    room.removeCorner(index)
                    selectedWall = nil
                    deletedCount += 1
                }
            }
        case .feature(let id):
            selectedFeatureID = id
        default:
            break
        }
    }

    private func tap(at location: CGPoint, space: CanvasSpace) {
        switch target {
        case .wall(let wall):
            selectedWall = (selectedWall == wall) ? nil : wall
            selectedFeatureID = nil
        case .empty:
            willEdit()
            room.insertCorner(at: space.roomPoint(location))
            selectedWall = nil
        case .corner, .feature, .none:
            break
        }
    }

    /// Corners win over features, features over walls.
    private func hitTest(_ location: CGPoint, space: CanvasSpace) -> Target {
        let corners = room.corners
        let points = corners.map { space.viewPoint($0) }

        if let nearest = points.indices.min(by: { distance(points[$0], location) < distance(points[$1], location) }),
           distance(points[nearest], location) <= cornerReach {
            return .corner(nearest)
        }

        for feature in room.features {
            let spot = space.viewPoint(PlanGeometry.point(onWall: feature.wall, offset: feature.offsetCm, corners: corners))
            if distance(spot, location) <= featureReach {
                return .feature(feature.id)
            }
        }

        let hit = PlanGeometry.nearestWall(to: space.roomPoint(location), corners: corners)
        let onWall = space.viewPoint(PlanGeometry.point(onWall: hit.wall, offset: hit.offset, corners: corners))
        if distance(onWall, location) <= wallReach {
            return .wall(hit.wall)
        }
        return .empty
    }

    /// Moves a door, window, or outlet to the closest spot on any wall.
    private func slideFeature(_ id: UUID, to point: Point2D) {
        guard let index = room.features.firstIndex(where: { $0.id == id }) else { return }
        let target = PlanGeometry.nearestWall(to: point, corners: room.corners)
        let wallLength = PlanGeometry.wallLength(target.wall, corners: room.corners)
        room.features[index].wall = target.wall
        room.features[index].offsetCm = PlanGeometry.clampOffset(
            target.offset,
            width: room.features[index].widthCm,
            wallLength: wallLength
        )
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

// MARK: - Drawing

/// The extra layers the advanced builder draws around `RoomPlanPainter`:
/// a measuring grid, the selected wall, corner handles, and angles.
enum AdvancedPlanPainter {
    /// Light lines every 50 cm, or every foot in imperial.
    static func paintGrid(_ ctx: inout GraphicsContext, size: CGSize, space: CanvasSpace, unit: UnitSystem) {
        let step = unit == .metric ? 50.0 : Length.cmPerFoot
        let topLeft = space.roomPoint(.zero)
        let bottomRight = space.roomPoint(CGPoint(x: size.width, y: size.height))
        var grid = Path()

        var x = (topLeft.x / step).rounded(.down) * step
        while x <= bottomRight.x {
            let p = space.viewPoint(Point2D(x: x, y: 0))
            grid.move(to: CGPoint(x: p.x, y: 0))
            grid.addLine(to: CGPoint(x: p.x, y: size.height))
            x += step
        }
        var y = (topLeft.y / step).rounded(.down) * step
        while y <= bottomRight.y {
            let p = space.viewPoint(Point2D(x: 0, y: y))
            grid.move(to: CGPoint(x: 0, y: p.y))
            grid.addLine(to: CGPoint(x: size.width, y: p.y))
            y += step
        }
        ctx.stroke(grid, with: .color(Theme.line.opacity(0.7)), lineWidth: 0.5)
    }

    static func paintEditing(
        _ ctx: inout GraphicsContext,
        corners: [Point2D],
        selectedWall: Int?,
        activeCorner: Int?,
        uncertainWalls: [Int] = [],
        space: CanvasSpace
    ) {
        let count = corners.count
        guard count >= 3 else { return }
        let points = corners.map { space.viewPoint($0) }

        // Walls a scan wasn't sure about: a dashed warning line to check.
        for wall in uncertainWalls where corners.indices.contains(wall) {
            var line = Path()
            line.move(to: points[wall])
            line.addLine(to: points[(wall + 1) % count])
            ctx.stroke(line, with: .color(Theme.danger.opacity(0.8)), style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [8, 6]))
        }

        if let wall = selectedWall, corners.indices.contains(wall) {
            var line = Path()
            line.move(to: points[wall])
            line.addLine(to: points[(wall + 1) % count])
            // See-through, so a window or door on the wall still shows.
            ctx.stroke(line, with: .color(Theme.accent.opacity(0.45)), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        }

        for i in 0..<count {
            // The angle, drawn just inside the corner.
            let angle = PolygonGeometry.interiorAngle(at: i, corners: corners)
            let label = Text("\(Int(angle.rounded()))°")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
            ctx.draw(label, at: insidePoint(at: i, points: points, angle: angle), anchor: .center)

            // The handle.
            let active = i == activeCorner
            let radius: CGFloat = active ? 11 : 8
            let handle = Path(ellipseIn: CGRect(
                x: points[i].x - radius,
                y: points[i].y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            ctx.fill(handle, with: .color(active ? Theme.accent : Theme.surface))
            ctx.stroke(handle, with: .color(Theme.accent), lineWidth: 2.5)
        }
    }

    /// A spot about 28 points inside the room from corner `i`, along the
    /// line that splits the corner's angle in half.
    private static func insidePoint(at i: Int, points: [CGPoint], angle: Double) -> CGPoint {
        let count = points.count
        let corner = points[i]
        func unit(_ to: CGPoint) -> CGPoint {
            let dx = to.x - corner.x
            let dy = to.y - corner.y
            let length = max(hypot(dx, dy), 0.001)
            return CGPoint(x: dx / length, y: dy / length)
        }
        let toPrevious = unit(points[(i - 1 + count) % count])
        let toNext = unit(points[(i + 1) % count])
        var bisector = CGPoint(x: toPrevious.x + toNext.x, y: toPrevious.y + toNext.y)
        let length = hypot(bisector.x, bisector.y)

        if length < 0.01 {
            // A straight 180° corner: step off the wall into the room.
            bisector = CGPoint(x: -toNext.y, y: toNext.x)
        } else {
            bisector = CGPoint(x: bisector.x / length, y: bisector.y / length)
            // Past 180° the halfway line points out of the room; flip it.
            if angle > 180 {
                bisector = CGPoint(x: -bisector.x, y: -bisector.y)
            }
        }
        return CGPoint(x: corner.x + bisector.x * 28, y: corner.y + bisector.y * 28)
    }
}
