import SwiftUI
import SwiftData

/// Pick furniture you've already added (in other rooms, or not in any
/// room yet) and put it in this room too. It keeps its other rooms.
struct AddExistingFurnitureSheet: View {
    let room: Room

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.createdAt) private var allItems: [Item]

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue
    @State private var chosen: Set<UUID> = []
    @State private var search = ""
    /// Take the pieces out of their other rooms too.
    @State private var moveHere = false

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }
    private var candidates: [Item] {
        let all = RoomFurniture.addable(allItems, to: room)
        let text = search.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(text) || $0.type.displayName.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    EmptyState(
                        systemImage: "checkmark.circle",
                        title: "Everything's already here",
                        message: "All your furniture is already in \(room.name). Add a new piece instead.",
                        actionTitle: "Done"
                    ) { dismiss() }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.sm + 4), GridItem(.flexible(), spacing: Theme.Space.sm + 4)],
                                  spacing: Theme.Space.sm + 4) {
                            ForEach(candidates) { item in
                                let isChosen = chosen.contains(item.uuid)
                                Button {
                                    if isChosen { chosen.remove(item.uuid) } else { chosen.insert(item.uuid) }
                                } label: {
                                    ItemCard(item: item, unit: unit)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                                .stroke(Theme.accent, lineWidth: isChosen ? 3 : 0)
                                        )
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 24))
                                                .foregroundStyle(isChosen ? Theme.accent : Theme.textSecondary)
                                                .background(Circle().fill(Theme.surface))
                                                .padding(10)
                                        }
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityAddTraits(isChosen ? .isSelected : [])
                                .accessibilityHint(isChosen ? "Won't be added" : "Will be added to \(room.name)")
                            }
                        }
                        .padding(Theme.Space.md)
                    }
                    .searchable(text: $search, prompt: "Search your furniture")
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: Theme.Space.sm) {
                            Toggle(isOn: $moveHere) {
                                Text("Move here (take out of other rooms)")
                                    .font(Typography.subheadline)
                            }
                            .tint(Theme.accent)
                        PrimaryButton(title: chosen.isEmpty ? "Choose furniture" : "Add \(chosen.count) to \(room.name)",
                                      systemImage: "plus") { add() }
                            .disabled(chosen.isEmpty)
                            .opacity(chosen.isEmpty ? 0.5 : 1)
                        }
                        .padding(Theme.Space.md)
                        .background(Theme.background)
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Add existing furniture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.frame(minHeight: Theme.minTap)
                }
            }
        }
    }

    private func add() {
        for item in allItems where chosen.contains(item.uuid) {
            if moveHere {
                RoomFurniture.move(item, to: room)
            } else {
                RoomFurniture.add(item, to: room)
            }
        }
        try? context.save()
        dismiss()
    }
}

extension RoomFurniture {
    /// Furniture that isn't in this room yet ("any room" pieces already are).
    @MainActor
    static func addable(_ items: [Item], to room: Room) -> [Item] {
        items.filter { !$0.belongs(to: room) }
    }

    /// Puts an item in this room only, taking it out of its other rooms.
    @MainActor
    static func move(_ item: Item, to room: Room) {
        item.setRooms([room], anyRoom: false)
    }

    /// Puts an item in this room as well, keeping its other rooms.
    @MainActor
    static func add(_ item: Item, to room: Room) {
        guard !item.belongs(to: room) else { return }
        item.setRooms(item.assignedRooms + [room], anyRoom: false)
    }
}
