import SwiftUI

/// Pick the rooms a piece of furniture could go in: none, one, several, or
/// "Any room" when it isn't settled yet. Tapping a room adds or removes it.
struct RoomChooser: View {
    @Binding var rooms: [Room]
    @Binding var anyRoom: Bool
    let allRooms: [Room]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Rooms")
                .font(Typography.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(summary)
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: Theme.Space.sm) {
                Chip(title: "Any room · not sure yet", systemImage: "questionmark.square.dashed", isSelected: anyRoom) {
                    anyRoom.toggle()
                    if anyRoom { rooms = [] }
                }
                .accessibilityHint("Shows this piece in layouts for every room")

                ForEach(allRooms) { room in
                    let selected = !anyRoom && rooms.contains { $0.uuid == room.uuid }
                    Chip(title: room.name, systemImage: selected ? "checkmark" : nil, isSelected: selected) {
                        toggle(room)
                    }
                    .accessibilityHint(selected ? "Removes it from this room" : "Adds it to this room")
                }
            }
        }
    }

    private var summary: String {
        if anyRoom { return "It'll be included in layouts for every room until you decide." }
        switch rooms.count {
        case 0: return allRooms.isEmpty ? "Add a room to place this piece." : "Not in a room yet. Pick one or more."
        case 1: return "Used in layouts for \(rooms[0].name)."
        default: return "Used in layouts for \(rooms.map(\.name).formatted(.list(type: .and)))."
        }
    }

    private func toggle(_ room: Room) {
        anyRoom = false
        if let index = rooms.firstIndex(where: { $0.uuid == room.uuid }) {
            rooms.remove(at: index)
        } else {
            rooms.append(room)
        }
    }
}
