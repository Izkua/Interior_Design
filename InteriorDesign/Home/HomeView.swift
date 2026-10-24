import SwiftUI
import SwiftData

/// Screens Home can open. Also used by onboarding to land on the room list.
enum HomeRoute: Hashable {
    case layouts
    case rooms
}

struct HomeView: View {
    @Binding var selectedTab: AppTab
    /// Owned by RootView, so onboarding can open a screen here.
    @Binding var path: [HomeRoute]

    @Query private var items: [Item]
    @Query(sort: \Room.updatedAt, order: .reverse) private var rooms: [Room]

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue


    private var itemsSubtitle: String {
        switch items.count {
        case 0: return "Add the furniture you already own"
        case 1: return "1 item in your space"
        default: return "\(items.count) items in your space"
        }
    }

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    if let room = rooms.first {
                        SectionHeader(title: "Continue where you left off", actionTitle: "All rooms") {
                            path.append(.rooms)
                        }
                        NavigationLink {
                            RoomBuilderView(room: room)
                        } label: {
                            ContinueRoomCard(room: room, unit: unit)
                        }
                        .buttonStyle(PressableStyle())
                        .padding(.bottom, Theme.Space.sm)
                    }

                    Text("What would you like to do?")
                        .font(Typography.body)
                        .foregroundStyle(Theme.textSecondary)

                    HomeCard(
                        title: "Current Items",
                        subtitle: itemsSubtitle,
                        systemImage: "sofa"
                    ) {
                        selectedTab = .items
                    }

                    HomeCard(
                        title: "Shopping",
                        subtitle: "Find pieces that fit your room and budget",
                        systemImage: "bag"
                    ) {
                        selectedTab = .catalog
                    }

                    HomeCard(
                        title: "Recommended Layouts",
                        subtitle: "See ways to arrange your room",
                        systemImage: "square.split.2x2"
                    ) {
                        path.append(.layouts)
                    }
                }
                .padding(Theme.Space.md)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Home")
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .layouts:
                    RecommendedLayoutsView()
                case .rooms:
                    RoomListView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
        }
    }
}

/// The most recently edited room, so the person can pick up where they
/// stopped.
private struct ContinueRoomCard: View {
    let room: Room
    let unit: UnitSystem

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
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the room builder")
    }
}

private struct HomeCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppCard {
                HStack(spacing: Theme.Space.md) {
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 56, height: 56)
                        .background(Theme.accent.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(title)
                            .font(Typography.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(subtitle)
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 72)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(title)")
    }
}
