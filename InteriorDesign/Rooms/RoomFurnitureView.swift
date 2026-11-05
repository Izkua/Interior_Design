import SwiftUI
import SwiftData

/// The "Furniture" page of a room: where its furniture stands now (the
/// saved layout), what isn't placed yet, and ways to change it.
struct RoomFurnitureView: View {
    let room: Room

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue
    @State private var showAddItem = false
    /// What's open on top: moving furniture by hand, or the suggestions.
    @State private var arranging: LayoutSuggestion?
    @State private var showSuggestions = false

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    var body: some View {
        // Worked out once per redraw: the furniture and where each piece is.
        let items = room.layoutItems
        let placed = RoomFurniture.placed(items)
        let unplaced = RoomFurniture.unplaced(items)
        let problemIDs = RoomFurniture.problemIDs(placed, room: room.layoutRoom)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                if items.isEmpty {
                    EmptyState(
                        systemImage: "sofa",
                        title: "No furniture in \(room.name) yet",
                        message: "Add the pieces you own to this room, then arrange them.",
                        actionTitle: "Add an item"
                    ) { showAddItem = true }
                } else {
                    AppCard(padding: 0) {
                        LayoutPlanView(room: room.layoutRoom, placed: placed, unit: unit, problemIDs: problemIDs)
                            .frame(height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }

                    if room.chosenLayout == nil {
                        note("Place your furniture where it is today. \"Place all\" puts everything in a sensible spot to start; then drag pieces to where they really are.")
                    } else if let label = room.chosenLayout?.label {
                        note(label.hasPrefix("Current arrangement")
                             ? "This is how your furniture is arranged now. Use Move furniture to change it."
                             : "Arranged like the suggested layout \"\(label)\". Use Move furniture to change it.")
                    }
                    if !problemIDs.isEmpty {
                        Label("\(problemIDs.count == 1 ? "1 piece is" : "\(problemIDs.count) pieces are") outside the room, overlapping, or blocking a door or path (shown in red). Use Move furniture to fix it.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !unplaced.isEmpty {
                        AppCard {
                            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                                SectionHeader(title: "Not placed yet")
                                Text(unplaced.map(\.name).joined(separator: ", "))
                                    .font(Typography.body)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }

                    Button {
                        arranging = room.chosenLayout == nil
                            ? RoomFurniture.placeAll(items, room: room.layoutRoom)
                            : RoomFurniture.currentSuggestion(items, room: room.layoutRoom)
                    } label: {
                        Label(room.chosenLayout == nil ? "Place all" : "Move furniture", systemImage: "hand.draw")
                            .font(Typography.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(PressableStyle())

                    Button {
                        showSuggestions = true
                    } label: {
                        Label("See suggested layouts", systemImage: "square.split.2x2")
                            .font(Typography.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(Theme.Space.md)
        }
        .sheet(isPresented: $showAddItem) { ItemEditorSheet(item: nil, defaultRoom: room) }
        // Sheets, not pushed screens: a screen pushed from this already
        // pushed one can loop forever on iOS 26 (see ProductDetailView).
        .sheet(item: $arranging) { suggestion in
            NavigationStack {
                LayoutDetailView(room: room, suggestion: suggestion, missing: [])
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { arranging = nil }.frame(minHeight: Theme.minTap)
                        }
                    }
            }
            // Dragging furniture shouldn't close the sheet.
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showSuggestions) {
            NavigationStack {
                RecommendedLayoutsView(initialRoomID: room.uuid)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showSuggestions = false }.frame(minHeight: Theme.minTap)
                        }
                    }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The room's furniture split by whether it has a spot in the saved layout.
/// Kept apart from the screen so it can be tested.
enum RoomFurniture {
    static func placed(_ items: [LayoutItem]) -> [PlacedItem] {
        items.compactMap { item in item.current.map { PlacedItem(item: item, placement: $0) } }
    }

    static func unplaced(_ items: [LayoutItem]) -> [LayoutItem] {
        items.filter { $0.current == nil }
    }

    /// The current arrangement as a starting point for moving things by
    /// hand. Pieces with no spot yet start in the middle of the room, side
    /// by side, ready to be dragged where they really are.
    static func currentSuggestion(_ items: [LayoutItem], room: LayoutRoom) -> LayoutSuggestion {
        var placements = items.compactMap(\.current)
        let middle = room.centroid
        for (index, item) in unplaced(items).enumerated() {
            let offset = Double(index) * 25
            placements.append(ItemPlacement(itemID: item.id, x: middle.x + offset, y: middle.y + offset, rotation: 0))
        }
        return LayoutSuggestion(label: "Current arrangement", placements: placements, leftOut: [], score: 0, breakdown: LayoutScore())
    }

    /// A first arrangement from the layout engine, to adjust by hand.
    static func placeAll(_ items: [LayoutItem], room: LayoutRoom) -> LayoutSuggestion {
        guard var first = LayoutEngine.suggest(room: room, items: items).first else {
            return currentSuggestion(items, room: room)
        }
        first.label = "Current arrangement"
        return first
    }

    /// Pieces that break a rule where they stand: outside the room,
    /// overlapping, or blocking a door or path. Shown, never blocked.
    static func problemIDs(_ placed: [PlacedItem], room: LayoutRoom) -> Set<UUID> {
        guard !placed.isEmpty else { return [] }
        return Set(LayoutRules(room: room).problems(in: placed).flatMap(\.itemIDs))
    }
}

extension LayoutRoom {
    /// The average of the corners: the middle of the room for most shapes.
    var centroid: Point2D {
        guard !corners.isEmpty else { return Point2D(x: 0, y: 0) }
        let n = Double(corners.count)
        return Point2D(x: corners.map(\.x).reduce(0, +) / n, y: corners.map(\.y).reduce(0, +) / n)
    }
}
