import SwiftUI
import SwiftData

/// All saved rooms. Pushed from the room layout button on Current Items
/// and from Home. It is pushed rather than shown as a sheet so dragging a
/// door down the plan can never swipe the screen away.
struct RoomListView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Room.updatedAt, order: .reverse) private var rooms: [Room]

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue

    @State private var newRoom: Room?
    @State private var roomToDelete: Room?
    @State private var roomToRename: Room?
    @State private var draftName = ""

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    var body: some View {
        Group {
            if rooms.isEmpty {
                EmptyState(
                    systemImage: "square.dashed",
                    title: "No rooms yet",
                    message: "Add your room's shape and size, then place doors and windows.",
                    actionTitle: "Create a room",
                    action: addRoom
                )
            } else {
                List {
                    ForEach(rooms) { room in
                        NavigationLink {
                            RoomBuilderView(room: room)
                        } label: {
                            RoomRow(room: room, unit: unit)
                        }
                        .listRowBackground(Theme.surface)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Not role: .destructive, which removes the row
                            // before the person has confirmed.
                            Button {
                                roomToDelete = room
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(Theme.danger)

                            Button {
                                startRename(room)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(Theme.textSecondary)
                        }
                        .contextMenu {
                            Button {
                                startRename(room)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                roomToDelete = room
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Rooms")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $newRoom) { room in
            RoomBuilderView(room: room)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ToolbarIconButton(systemName: "plus", label: "New room", action: addRoom)
                ProfileButton()
            }
        }
        .alert("Rename room", isPresented: renameIsPresented) {
            TextField("Room name", text: $draftName)
            Button("Save") { roomToRename?.rename(draftName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \(roomToDelete?.name ?? "this room")?",
            isPresented: deleteIsPresented,
            titleVisibility: .visible
        ) {
            Button("Delete room", role: .destructive) {
                if let room = roomToDelete { delete(room) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your items stay in Current Items.")
        }
    }

    private var renameIsPresented: Binding<Bool> {
        Binding(get: { roomToRename != nil }, set: { if !$0 { roomToRename = nil } })
    }

    private var deleteIsPresented: Binding<Bool> {
        Binding(get: { roomToDelete != nil }, set: { if !$0 { roomToDelete = nil } })
    }

    private func startRename(_ room: Room) {
        draftName = room.name
        roomToRename = room
    }

    private func addRoom() {
        let room = Room(name: "Room \(rooms.count + 1)", width: 400, length: 500)
        context.insert(room)
        try? context.save()
        newRoom = room
    }

    private func delete(_ room: Room) {
        context.delete(room)
        try? context.save()
        roomToDelete = nil
    }
}

private struct RoomRow: View {
    let room: Room
    let unit: UnitSystem

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            RoomThumbnail(corners: room.corners)
                .frame(width: 64, height: 64)
                .background(
                    Theme.surfaceAlt,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(Typography.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("\(Length.format(room.width, system: unit)) × \(Length.format(room.length, system: unit))")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: Theme.minTap)
    }
}
