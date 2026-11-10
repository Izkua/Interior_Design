import UIKit

extension Item {
    /// The piece's main color, if it has a photo. Call `refreshColor()`
    /// first so it's up to date.
    var mainColor: RGB? {
        guard let key = colorKey, let hex = key.split(separator: "|").first else { return nil }
        return RGB(hex: String(hex))
    }

    /// Works out the main color from the cutout (or else the photo) when
    /// it's missing or the picture changed. All on the phone.
    @MainActor
    func refreshColor() {
        guard let data = cutoutData ?? photoData else {
            if colorKey != nil { colorKey = nil }
            return
        }
        let size = "\(data.count)"
        if let key = colorKey, key.hasSuffix("|" + size) { return }
        guard let image = UIImage(data: data) else { return }
        colorKey = PhotoColors.colors(from: image, type: type).main.hex + "|" + size
    }
}

extension Room {
    /// The room's color mood, from the photos of everything in it. Bigger
    /// pieces count more. Nil when no piece has a photo yet.
    @MainActor
    func vibe() -> RoomVibe? {
        let colors: [(color: RGB, weight: Double)] = allItems.compactMap { item in
            item.refreshColor()
            guard let color = item.mainColor else { return nil }
            // What you see of it: the front, or the top for a rug.
            let area = item.type == .rug ? item.widthCm * item.depthCm : item.widthCm * item.heightCm
            return (color, max(area, 100))
        }
        return RoomVibe.from(colors)
    }
}
