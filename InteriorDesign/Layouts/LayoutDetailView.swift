import SwiftUI
import SwiftData

/// One suggested layout up close: what stays, what moves, what is missing.
/// Drag items to adjust them, then save it as the room's layout.
///
/// In preview mode it shows a catalog product placed among the room's
/// furniture instead; nothing is saved.
struct LayoutDetailView: View {
    let room: Room
    let suggestion: LayoutSuggestion
    let missing: [MissingPiece]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allRooms: [Room]

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue

    /// The layout as adjusted by hand; starts as the suggestion.
    @State private var placements: [ItemPlacement]
    @State private var selectedID: UUID?
    @State private var dragStart: ItemPlacement?
    @State private var frozenSpace: CanvasSpace?
    @State private var confirmProblems = false

    private let items: [LayoutItem]
    private let rules: LayoutRules
    /// A product being tried out, in preview mode.
    private let previewItem: LayoutItem?

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    init(room: Room, suggestion: LayoutSuggestion, missing: [MissingPiece]) {
        self.room = room
        self.suggestion = suggestion
        self.missing = missing
        items = room.layoutItems
        rules = LayoutRules(room: room.layoutRoom)
        previewItem = nil
        _placements = State(initialValue: suggestion.placements)
    }

    /// Preview mode: the room's furniture where it stands now plus a
    /// product. `furniture` is worked out by the caller, off the main
    /// thread (see `CatalogStore.furniturePlacements`).
    init(room: Room, furniture placements: [ItemPlacement], preview: (item: LayoutItem, placement: ItemPlacement)) {
        self.room = room
        self.suggestion = LayoutSuggestion(label: "Preview", placements: placements + [preview.placement], leftOut: [], score: 0, breakdown: LayoutScore())
        self.missing = []
        items = room.layoutItems + [preview.item]
        rules = LayoutRules(room: room.layoutRoom)
        previewItem = preview.item
        _placements = State(initialValue: placements + [preview.placement])
    }

    private var itemsByID: [UUID: LayoutItem] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    private var placed: [PlacedItem] {
        placements.compactMap { p in itemsByID[p.itemID].map { PlacedItem(item: $0, placement: p) } }
    }

    private var isAdjusted: Bool { placements != suggestion.placements }

    var body: some View {
        // Worked out once per redraw and shared below.
        let problems = rules.problems(in: placed)
        let names = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.name) })

        VStack(spacing: 0) {
            AppCard(padding: 0) {
                VStack(spacing: 0) {
                    plan(problemIDs: Set(problems.flatMap(\.itemIDs)))
                        .frame(height: 320)
                        .clipped()
                    Divider()
                    controls
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.sm)

            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    if !problems.isEmpty {
                        problemsCard(problems, names: names)
                    }
                    changesCard
                    if !sharedNotes.isEmpty {
                        sharedCard
                    }
                    if !missing.isEmpty {
                        missingCard
                    }
                    if let previewItem {
                        AppCard {
                            Text("This is a preview of \(previewItem.name) in \(room.name). Drag it around to try spots. Nothing is saved; once you own it, add it in Current Items.")
                                .font(Typography.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        PrimaryButton(title: "Use this layout", systemImage: "checkmark") {
                            if problems.isEmpty { save() } else { confirmProblems = true }
                        }
                    }
                    VisualizeButton(room: room, placements: placements, items: items, style: .tinted)
                }
                .padding(Theme.Space.md)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(previewItem != nil ? "Preview" : isAdjusted ? "\(suggestion.label) (adjusted)" : suggestion.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
        }
        .confirmationDialog("This layout breaks some rules", isPresented: $confirmProblems, titleVisibility: .visible) {
            Button("Save anyway") { save() }
            Button("Keep adjusting", role: .cancel) {}
        } message: {
            Text("Something is blocked or doesn't fit. You can still save it and fix it later.")
        }
    }

    // MARK: Plan and dragging

    private func plan(problemIDs: Set<UUID>) -> some View {
        GeometryReader { geo in
            let space = frozenSpace ?? LayoutPlanView.fit(room.layoutRoom, placed, size: geo.size)
            LayoutPlanView(
                room: room.layoutRoom,
                placed: placed,
                unit: unit,
                selectedID: selectedID,
                problemIDs: problemIDs,
                space: space
            )
            .contentShape(Rectangle())
            .gesture(dragGesture(space: space))
        }
    }

    private func dragGesture(space: CanvasSpace) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil {
                    frozenSpace = space
                    selectedID = hit(value.startLocation, space: space)
                    dragStart = placements.first { $0.itemID == selectedID }
                }
                guard let start = dragStart,
                      let index = placements.firstIndex(where: { $0.itemID == start.itemID }),
                      itemsByID[start.itemID]?.isFixed == false
                else { return }
                // Follow the finger, snapping to 5 cm.
                let dx = Double(value.translation.width / space.scale)
                let dy = Double(value.translation.height / space.scale)
                placements[index].x = ((start.x + dx) / 5).rounded() * 5
                placements[index].y = ((start.y + dy) / 5).rounded() * 5
            }
            .onEnded { _ in
                dragStart = nil
                frozenSpace = nil
            }
    }

    /// The item under the finger. Furniture wins over rugs.
    private func hit(_ location: CGPoint, space: CanvasSpace) -> UUID? {
        let point = space.roomPoint(location)
        let slop = 8 / space.scale
        let under = placed.filter { $0.footprint.expanded(by: slop).contains(point) }
        return (under.first { !$0.item.liesFlat } ?? under.first)?.item.id
    }

    private var controls: some View {
        HStack(spacing: Theme.Space.sm) {
            if let id = selectedID, let item = itemsByID[id] {
                Text(item.isFixed ? "\(item.name) is fixed in place" : item.name)
                    .font(Typography.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                IconButton(systemName: "rotate.right", label: "Turn \(item.name)") { rotate(id) }
                    .disabled(item.isFixed)
                    .opacity(item.isFixed ? 0.4 : 1)
            } else {
                Text("Drag an item to move it.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            IconButton(systemName: "arrow.counterclockwise", label: "Back to the suggestion") {
                placements = suggestion.placements
                selectedID = nil
            }
            .disabled(!isAdjusted)
            .opacity(isAdjusted ? 1 : 0.4)
        }
        .padding(.horizontal, Theme.Space.sm + 4)
        .padding(.vertical, Theme.Space.sm)
    }

    private func rotate(_ id: UUID) {
        guard let index = placements.firstIndex(where: { $0.itemID == id }) else { return }
        placements[index].rotation = (placements[index].rotation + 90) % 360
    }

    // MARK: Cards

    private func problemsCard(_ problems: [LayoutProblem], names: [UUID: String]) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Label("Check these", systemImage: "exclamationmark.triangle.fill")
                    .font(Typography.headline)
                    .foregroundStyle(Theme.danger)
                // The first few are enough to act on; a wall of red is not.
                ForEach(Array(problems.prefix(4).enumerated()), id: \.offset) { _, problem in
                    Text("• " + problem.message(names: names))
                        .font(Typography.body)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if problems.count > 4 {
                    Text("and \(problems.count - 4) more")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    /// What stays, what moves, and what didn't fit.
    private var changesCard: some View {
        let groups: [(String, String, ItemChange)] = [
            ("Moves", "arrow.up.and.down.and.arrow.left.and.right", .moves),
            ("Placed", "plus.square.dashed", .placed),
            ("Stays where it is", "checkmark.circle", .stays),
            ("Didn't fit", "xmark.circle", .leftOut),
        ]
        return AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                SectionHeader(title: "Your furniture")
                ForEach(groups, id: \.0) { title, symbol, change in
                    let names = items
                        .filter { $0.id != previewItem?.id && ItemChange.of($0, in: placements) == change }
                        .map(\.name)
                    if !names.isEmpty {
                        HStack(alignment: .top, spacing: Theme.Space.sm + 4) {
                            Image(systemName: symbol)
                                .foregroundStyle(change == .leftOut ? Theme.danger : Theme.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                    .font(Typography.subheadline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(names.joined(separator: ", "))
                                    .font(Typography.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Furniture shared between rooms

    /// One line per piece in this layout that could also go elsewhere.
    private struct SharedNote: Identifiable {
        var id: UUID
        var text: String
        /// Set when the piece is also placed in another room's saved layout.
        var warning: String?
    }

    private var sharedNotes: [SharedNote] {
        let placedIDs = Set(placements.map(\.itemID))
        return room.allItems.compactMap { item in
            guard placedIDs.contains(item.uuid), previewItem?.id != item.uuid else { return nil }
            let others = item.assignedRooms.filter { $0.uuid != room.uuid }
            guard item.anyRoom || !others.isEmpty else { return nil }
            let text = item.anyRoom
                ? "\(item.name): not settled yet, shown in every room"
                : "\(item.name): also in \(others.map(\.name).formatted(.list(type: .and)))"
            // Other rooms whose saved layout already uses this piece.
            let elsewhere = item.savedLayoutRooms(among: allRooms, excluding: room)
            let warning = elsewhere.isEmpty ? nil
                : "It's also in your saved layout for \(elsewhere.map(\.name).formatted(.list(type: .and))). It can only be in one place at a time."
            return SharedNote(id: item.uuid, text: text, warning: warning)
        }
    }

    private var sharedCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                SectionHeader(title: "Shared with other rooms")
                ForEach(sharedNotes) { note in
                    HStack(alignment: .top, spacing: Theme.Space.sm + 4) {
                        Image(systemName: note.warning == nil ? "arrow.left.arrow.right" : "exclamationmark.circle")
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.text)
                                .font(Typography.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let warning = note.warning {
                                Text(warning)
                                    .font(Typography.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var missingCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                SectionHeader(title: "Could use")
                ForEach(missing, id: \.self) { piece in
                    HStack(alignment: .top, spacing: Theme.Space.sm + 4) {
                        Image(systemName: piece.type.symbol)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(piece.name)
                                .font(Typography.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            Text(piece.reason)
                                .font(Typography.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                Text("You'll be able to shop for these in the Catalog.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: Save

    private func save() {
        let result = LayoutEngine.score(placed, items: items, rules: rules)
        room.choose(
            placements,
            label: isAdjusted ? "\(suggestion.label) (adjusted)" : suggestion.label,
            score: result.score,
            context: context
        )
        dismiss()
    }
}
