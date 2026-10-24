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
    @State private var homePath: [HomeRoute] = []
    @State private var showAddItem = false

    @AppStorage(SettingsKey.didFinishOnboarding) private var didFinishOnboarding = false

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $tab) {
            HomeView(selectedTab: $tab, path: $homePath)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)

            CurrentItemsView(showAddItem: $showAddItem)
                .tabItem { Label("Current Items", systemImage: "sofa") }
                .tag(AppTab.items)

            CatalogView()
                .tabItem { Label("Catalog", systemImage: "bag") }
                .tag(AppTab.catalog)
        }
        .tint(Theme.accent)
        .fullScreenCover(isPresented: Binding(get: { !didFinishOnboarding }, set: { _ in })) {
            OnboardingView { next in
                didFinishOnboarding = true
                switch next {
                case .drawRoom:
                    tab = .home
                    homePath = [.rooms]
                case .addItem:
                    tab = .items
                    showAddItem = true
                case .explore:
                    tab = .home
                }
            }
        }
        .task {
            #if DEBUG
            SeedData.seedIfNeeded(context)
            #endif
        }
        // Email confirmation and sign-in links open the app.
        .onOpenURL { url in
            Task { await AuthStore.shared.handle(url: url) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Make sure edits are on disk whenever the app leaves the foreground.
            if phase != .active {
                try? context.save()
            }
        }
    }
}
