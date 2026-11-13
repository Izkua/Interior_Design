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
        let hungWithColor = Set(wallDecor.filter { !$0.colors.isEmpty }.compactMap(\.itemID))
        var colors: [(color: RGB, weight: Double)] = allItems.compactMap { item in
            // Picked colors win over the photo guess for hung pieces.
            guard !hungWithColor.contains(item.uuid) else { return nil }
            item.refreshColor()
            guard let color = item.mainColor else { return nil }
            // What you see of it: the front, or the top for a rug.
            let area = item.type == .rug ? item.widthCm * item.depthCm : item.widthCm * item.heightCm
            return (color, max(area, 100))
        }
        for piece in wallDecor {
            for (i, hex) in piece.colors.enumerated() {
                guard let color = RGB(hex: hex) else { continue }
                // The first color counts most.
                colors.append((color, piece.widthCm * piece.heightCm / Double(i + 1)))
            }
        }
        return RoomVibe.from(colors)
    }
}

extension Room {
    /// How warm or cool the room's main light is. Nil until set.
    var mainLightWarmth: LightWarmth? {
        get { mainLightWarmthRaw.flatMap(LightWarmth.init(rawValue:)) }
        set { mainLightWarmthRaw = newValue?.rawValue; updatedAt = Date() }
    }

    /// The room's light: its main light and its lamps' glow.
    var light: RoomLight {
        RoomLight(mainLight: mainLightWarmth,
                  lamps: allItems.filter { LightWarmth.isLight($0.type) }.compactMap(\.lightWarmth))
    }
}
