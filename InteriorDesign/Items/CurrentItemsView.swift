import SwiftUI
import SwiftData

struct CurrentItemsView: View {
    @Query(sort: \Item.createdAt) private var items: [Item]
    @Query(sort: \Room.updatedAt, order: .reverse) private var rooms: [Room]

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue

    @State private var showRooms = false
    @State private var showCapture = false
    /// Owned by RootView, so onboarding can open the add-item sheet.
    @Binding var showAddItem: Bool
    @State private var itemToEdit: Item?
    @State private var filter: RoomFilter = .all

    /// Which items to show.
    enum RoomFilter: Hashable {
        case all
        case room(UUID)
        case unassigned
    }

    private var shownItems: [Item] {
        switch filter {
        case .all: return items
        case .unassigned: return items.filter(\.isUnassigned)
        case .room(let id):
            guard let room = rooms.first(where: { $0.uuid == id }) else { return items }
            return items.filter { $0.belongs(to: room) }
        }
    }

    private var filteredRoom: Room? {
        if case .room(let id) = filter { return rooms.first { $0.uuid == id } }
        return nil
    }

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Space.sm + 4),
        GridItem(.flexible(), spacing: Theme.Space.sm + 4)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    EmptyState(
                        systemImage: "sofa",
                        title: "No items yet",
                        message: "Add the furniture you own to see layouts for your room.",
                        actionTitle: "Add an item"
                    ) {
                        showAddItem = true
                    }
                } else {
                    ScrollView {
                        if rooms.count > 0 {
                            filterBar
                        }
                        if shownItems.isEmpty {
                            Text(filter == .unassigned ? "Every piece is in a room." : "Nothing in this room yet. Add a piece, or edit one and pick this room.")
                                .font(Typography.body)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(Theme.Space.lg)
                        }
                        LazyVGrid(columns: columns, spacing: Theme.Space.sm + 4) {
                            ForEach(shownItems) { item in
                                Button {
                                    itemToEdit = item
                                } label: {
                                    ItemCard(item: item, unit: unit)
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityHint("Opens the item to edit it")
                            }
                        }
                        .padding(Theme.Space.md)
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Current Items")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ToolbarIconButton(systemName: "plus", label: "Add item") {
                        showAddItem = true
                    }
                }
                // Left to right: room layout, camera, profile.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ToolbarIconButton(systemName: "ruler", label: "Room layout") {
                        showRooms = true
                    }
                    ToolbarIconButton(systemName: "camera", label: "Take a photo of an item") {
                        showCapture = true
                    }
                    ProfileButton()
                }
            }
            .navigationDestination(isPresented: $showRooms) {
                RoomListView()
            }
            .sheet(isPresented: $showAddItem) {
                // New items go in the most recently edited room; the
                // person can pick another room or none.
                ItemEditorSheet(item: nil, defaultRoom: filteredRoom ?? rooms.first)
            }
            .sheet(item: $itemToEdit) { item in
                ItemEditorSheet(item: item)
            }
            .sheet(isPresented: $showCapture) {
                CaptureFlowView()
            }
        }
    }

    /// "All", each room, and "Not assigned", as chips that scroll sideways.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                Chip(title: "All", isSelected: filter == .all) { filter = .all }
                ForEach(rooms) { room in
                    Chip(title: room.name, isSelected: filter == .room(room.uuid)) { filter = .room(room.uuid) }
                }
                Chip(title: "Not assigned", isSelected: filter == .unassigned) { filter = .unassigned }
            }
            .padding(.horizontal, Theme.Space.md)
        }
        .padding(.top, Theme.Space.sm)
        .accessibilityLabel("Show items in")
    }
}
