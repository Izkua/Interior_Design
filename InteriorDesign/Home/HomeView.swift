import SwiftUI
import SwiftData

/// Screens Home can open. Also used by onboarding to land on the room list.
enum HomeRoute: Hashable {
    case rooms
}

/// Home shows one button per saved room, most recently edited first, so the
/// person can jump straight back into any room.
struct HomeView: View {
    /// Owned by RootView, so onboarding can open a screen here.
    @Binding var path: [HomeRoute]

    @Environment(\.modelContext) private var context

    @Query(sort: \Room.updatedAt, order: .reverse) private var rooms: [Room]

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue

    /// A room just made with "New room", opened in the builder right away.
    @State private var newRoom: Room?

    /// The room waiting on a rename or delete answer, if any.
    @State private var roomToRename: Room?
    @State private var roomToDelete: Room?
    @State private var draftName = ""

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    var body: some View {
        NavigationStack(path: $path) {
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
                    roomList
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Home")
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .rooms:
                    RoomListView()
                }
            }
            .navigationDestination(item: $newRoom) { room in
                RoomBuilderView(room: room)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
            .alert("Rename room", isPresented: renameIsPresented) {
                TextField("Room name", text: $draftName)
                Button("Save") {
                    roomToRename?.rename(draftName)
                    try? context.save()
                }
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
    }

    private var roomList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SectionHeader(title: "Your rooms")

                // Each room opens the builder when tapped. Its "•••" button
                // (or a long press) renames or deletes it, right here.
                ForEach(rooms) { room in
                    NavigationLink {
                        RoomBuilderView(room: room)
                    } label: {
                        RoomButton(room: room, unit: unit, isLatest: room.id == rooms.first?.id)
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu { roomActions(for: room) }
                    .overlay(alignment: .trailing) {
                        Menu {
                            roomActions(for: room)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: Theme.minTap, height: Theme.minTap)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("More options for \(room.name)")
                        .padding(.trailing, Theme.Space.xs)
                    }
                }

                NewRoomButton(action: addRoom)
            }
            .padding(Theme.Space.md)
        }
    }

    /// Rename and Delete, shared by the "•••" menu and the long-press menu.
    @ViewBuilder
    private func roomActions(for room: Room) -> some View {
        Button {
            draftName = room.name
            roomToRename = room
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button(role: .destructive) {
            roomToDelete = room
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var renameIsPresented: Binding<Bool> {
        Binding(get: { roomToRename != nil }, set: { if !$0 { roomToRename = nil } })
    }

    private var deleteIsPresented: Binding<Bool> {
        Binding(get: { roomToDelete != nil }, set: { if !$0 { roomToDelete = nil } })
    }

    private func delete(_ room: Room) {
        context.delete(room)
        try? context.save()
        roomToDelete = nil
    }

    private func addRoom() {
        let room = Room(name: "Room \(rooms.count + 1)", shape: .custom, width: 400, length: 500)
        context.insert(room)
        try? context.save()
        newRoom = room
    }
}

/// One saved room: its outline, name and size. The most recently edited
/// room is marked so the person can see where they left off.
private struct RoomButton: View {
    let room: Room
    let unit: UnitSystem
    let isLatest: Bool

    var body: some View {
        AppCard {
            HStack(spacing: Theme.Space.md) {
                RoomThumbnail(corners: room.corners)
                    .frame(width: 64, height: 64)
                    .background(
                        Theme.surfaceAlt,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(room.name)
                        .font(Typography.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(Length.format(room.width, system: unit)) × \(Length.format(room.length, system: unit))")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if isLatest {
                        Text("Last edited")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }

                Spacer(minLength: 0)

                // Room for the "•••" button HomeView lays on top.
                Color.clear
                    .frame(width: Theme.minTap, height: Theme.minTap)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the room builder")
    }
}

/// Adds a room and opens it in the builder.
private struct NewRoomButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
                Text("New room")
                    .font(Typography.headline)
            }
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 72)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}
