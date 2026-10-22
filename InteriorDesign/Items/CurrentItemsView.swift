import SwiftUI
import SwiftData

struct CurrentItemsView: View {
    @Query(sort: \Item.createdAt) private var items: [Item]

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue

    @State private var showRooms = false
    @State private var showCameraNote = false

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
                        actionTitle: "Set up your room"
                    ) {
                        showRooms = true
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: Theme.Space.sm + 4) {
                            ForEach(items) { item in
                                ItemCard(item: item, unit: unit)
                            }
                        }
                        .padding(Theme.Space.md)
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Current Items")
            .toolbar {
                // Left to right: room layout, camera, profile.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ToolbarIconButton(systemName: "ruler", label: "Room layout") {
                        showRooms = true
                    }
                    ToolbarIconButton(systemName: "camera", label: "Take a photo of an item") {
                        showCameraNote = true
                    }
                    ProfileButton()
                }
            }
            .navigationDestination(isPresented: $showRooms) {
                RoomListView()
            }
            .alert("Photo capture is coming soon", isPresented: $showCameraNote) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You'll be able to photograph a piece of furniture and have it labeled and sized for you.")
            }
        }
    }
}
