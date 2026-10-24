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
                        LazyVGrid(columns: columns, spacing: Theme.Space.sm + 4) {
                            ForEach(items) { item in
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
                ItemEditorSheet(item: nil, defaultRoom: rooms.first)
            }
            .sheet(item: $itemToEdit) { item in
                ItemEditorSheet(item: item)
            }
            .sheet(isPresented: $showCapture) {
                CaptureFlowView()
            }
        }
    }
}
