import SwiftUI
import SwiftData

@main
struct InteriorDesignApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Room.self,
            Item.self,
            RoomLayout.self,
            Preferences.self,
            Product.self
        ])
    }
}
