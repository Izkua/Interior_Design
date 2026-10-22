import SwiftUI
import SwiftData

/// The three bottom tabs, left to right.
enum AppTab: Hashable {
    case home
    case items
    case catalog
}

struct RootView: View {
    @State private var tab: AppTab = .home

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $tab) {
            HomeView(selectedTab: $tab)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)

            CurrentItemsView()
                .tabItem { Label("Current Items", systemImage: "sofa") }
                .tag(AppTab.items)

            CatalogView()
                .tabItem { Label("Catalog", systemImage: "bag") }
                .tag(AppTab.catalog)
        }
        .tint(Theme.accent)
        .task {
            #if DEBUG
            SeedData.seedIfNeeded(context)
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            // Make sure edits are on disk whenever the app leaves the foreground.
            if phase != .active {
                try? context.save()
            }
        }
    }
}
