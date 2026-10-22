#if DEBUG
import Foundation
import SwiftData

/// Sample data so every screen has something to show while building.
/// Compiled into debug builds only, so it never ships to the App Store.
enum SeedData {
    /// Adds the sample room and items once, on a fresh install.
    static func seedIfNeeded(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: SettingsKey.didSeedSampleData) else { return }
        let roomCount = (try? context.fetchCount(FetchDescriptor<Room>())) ?? 0
        let itemCount = (try? context.fetchCount(FetchDescriptor<Item>())) ?? 0
        guard roomCount == 0, itemCount == 0 else { return }
        insertSamples(context)
        UserDefaults.standard.set(true, forKey: SettingsKey.didSeedSampleData)
    }

    /// Also used by the "Load sample data" button in the profile sheet.
    static func insertSamples(_ context: ModelContext) {
        let room = Room(
            name: "Living room",
            width: 420,
            length: 360,
            features: [
                FixedFeature(kind: .door, wall: 2, offsetCm: 80, widthCm: 90),
                FixedFeature(kind: .window, wall: 0, offsetCm: 210, widthCm: 150),
                FixedFeature(kind: .outlet, wall: 3, offsetCm: 120, widthCm: 10),
                FixedFeature(kind: .outlet, wall: 1, offsetCm: 250, widthCm: 10)
            ]
        )
        context.insert(room)

        let items: [Item] = [
            Item(type: .sofa, name: "Sofa", widthCm: 210, depthCm: 90, heightCm: 85),
            Item(type: .table, name: "Coffee table", widthCm: 110, depthCm: 60, heightCm: 42),
            Item(type: .tvStand, name: "TV stand", widthCm: 150, depthCm: 40, heightCm: 50),
            Item(type: .chair, name: "Armchair", widthCm: 80, depthCm: 85, heightCm: 90),
            Item(type: .shelf, name: "Bookshelf", widthCm: 80, depthCm: 30, heightCm: 180),
            Item(type: .lamp, name: "Floor lamp", widthCm: 30, depthCm: 30, heightCm: 160, isEstimated: true)
        ]
        for item in items {
            context.insert(item)
            item.room = room
        }
        try? context.save()
    }
}
#endif
