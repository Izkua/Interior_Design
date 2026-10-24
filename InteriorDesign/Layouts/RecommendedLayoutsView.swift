import SwiftUI
import SwiftData

/// Suggested arrangements of a room's furniture. Swipe between options;
/// tap one to see what moves and to adjust it by hand.
struct RecommendedLayoutsView: View {
    @Query(sort: \Room.updatedAt, order: .reverse) private var rooms: [Room]

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue

    @State private var selectedRoomID: UUID?
    @State private var suggestions: [LayoutSuggestion] = []
    @State private var missing: [MissingPiece] = []
    @State private var isWorking = false
    /// Changing the seed asks the engine for a different set of ideas.
    @State private var seed: UInt64 = 42
    @State private var page = 0
    @State private var showRooms = false
    @State private var showAddItem = false

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    private var room: Room? {
        rooms.first { $0.uuid == selectedRoomID } ?? rooms.first
    }

    var body: some View {
        Group {
            if rooms.isEmpty {
                EmptyState(
                    systemImage: "square.dashed",
                    title: "No room yet",
                    message: "Draw your room first, then layouts for it will appear here.",
                    actionTitle: "Create a room"
                ) { showRooms = true }
            } else if let room, room.items.isEmpty {
                EmptyState(
                    systemImage: "sofa",
                    title: "No furniture in \(room.name)",
                    message: "Add the pieces you own to this room to see ways to arrange them.",
                    actionTitle: "Add an item"
                ) { showAddItem = true }
                .safeAreaInset(edge: .top) { roomPicker.padding(.horizontal, Theme.Space.md) }
            } else if let room {
                content(room)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Recommended Layouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
        }
        .navigationDestination(isPresented: $showRooms) { RoomListView() }
        .sheet(isPresented: $showAddItem) { ItemEditorSheet(item: nil, defaultRoom: room) }
        .task(id: "\(room?.layoutSignature ?? "")#\(seed)") { await generate() }
    }

    // MARK: Suggestions

    private func content(_ room: Room) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack {
                    roomPicker
                    Spacer()
                    Button {
                        seed &+= 1
                    } label: {
                        Label("More ideas", systemImage: "shuffle")
                            .font(Typography.subheadline)
                            .frame(minHeight: Theme.minTap)
                    }
                    .disabled(isWorking)
                }

                if suggestions.isEmpty {
                    // A plain outline of the room while the engine works.
                    AppCard {
                        VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                            Text("Arranging your furniture…")
                                .font(Typography.title)
                                .foregroundStyle(Theme.textSecondary)
                            LayoutPlanView(room: room.layoutRoom, placed: [], unit: unit, showWallLengths: false)
                                .frame(height: 320)
                                .opacity(0.5)
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .accessibilityElement(children: .combine)
                } else if suggestions[0].placements.isEmpty {
                    tooBigCard(room)
                } else {
                    TabView(selection: $page) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                            NavigationLink {
                                LayoutDetailView(room: room, suggestion: suggestion, missing: missing)
                            } label: {
                                optionCard(room, suggestion, number: index + 1)
                            }
                            .buttonStyle(PressableStyle())
                            .padding(.horizontal, 2)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 470)

                    pageDots
                }

                if suggestions.indices.contains(page), !suggestions[page].placements.isEmpty {
                    VisualizeButton(room: room, placements: suggestions[page].placements, items: room.layoutItems)
                }
            }
            .padding(Theme.Space.md)
        }
    }

    private func optionCard(_ room: Room, _ suggestion: LayoutSuggestion, number: Int) -> some View {
        let items = room.layoutItems
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let placed = suggestion.placements.compactMap { p in byID[p.itemID].map { PlacedItem(item: $0, placement: p) } }
        let leftOut = suggestion.leftOut.compactMap { byID[$0]?.name }

        return AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Option \(number) of \(suggestions.count)")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Text(suggestion.label)
                            .font(Typography.title)
                            .foregroundStyle(Theme.textPrimary)
                        if isCurrent(items, suggestion) {
                            Tag(text: "Your current layout")
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }

                LayoutPlanView(room: room.layoutRoom, placed: placed, unit: unit, showWallLengths: false)
                    .frame(height: 320)
                    .background(Theme.surfaceAlt.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))

                if leftOut.isEmpty {
                    Text("Everything fits. Tap to see what moves or adjust it.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Didn't fit: \(leftOut.joined(separator: ", "))")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.danger)
                }
            }
        }
    }

    /// True when nothing would move: this is the layout already chosen.
    private func isCurrent(_ items: [LayoutItem], _ suggestion: LayoutSuggestion) -> Bool {
        items.contains { $0.current != nil }
            && items.allSatisfy { ItemChange.of($0, in: suggestion.placements) == .stays }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(suggestions.indices, id: \.self) { index in
                Circle()
                    .fill(index == page ? Theme.accent : Theme.line)
                    .frame(width: 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Option \(page + 1) of \(suggestions.count). Swipe for more.")
    }

    /// Shown when not a single item fits in the room.
    private func tooBigCard(_ room: Room) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Label("Your items are too big for \(room.name)", systemImage: "exclamationmark.triangle.fill")
                    .font(Typography.headline)
                    .foregroundStyle(Theme.danger)
                Text("None of the furniture fits with room to walk and doors that open. Check the room's size and the items' sizes; one of them may be in the wrong units.")
                    .font(Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A menu to switch rooms, shown when there is more than one.
    @ViewBuilder
    private var roomPicker: some View {
        if let room {
            Menu {
                ForEach(rooms) { option in
                    Button(option.name) { selectedRoomID = option.uuid }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(room.name)
                    if rooms.count > 1 { Image(systemName: "chevron.down").font(.caption) }
                }
                .font(Typography.headline)
                .foregroundStyle(Theme.textPrimary)
                .frame(minHeight: Theme.minTap)
            }
            .disabled(rooms.count < 2)
        }
    }

    // MARK: Working out suggestions

    /// Runs the engine off the main thread so the screen never freezes.
    private func generate() async {
        guard let room, !room.items.isEmpty else {
            suggestions = []
            return
        }
        let layoutRoom = room.layoutRoom
        let items = room.layoutItems
        var options = LayoutEngine.Options()
        options.seed = seed
        isWorking = true
        suggestions = []
        let result = await Task.detached(priority: .userInitiated) {
            (LayoutEngine.suggest(room: layoutRoom, items: items, options: options), MissingPieces.suggest(for: items))
        }.value
        suggestions = result.0
        missing = result.1
        page = 0
        isWorking = false
    }
}
