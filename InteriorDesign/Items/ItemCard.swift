import SwiftUI
import UIKit

struct ItemCard: View {
    let item: Item
    let unit: UnitSystem

    var body: some View {
        AppCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Theme.surfaceAlt
                    if let data = item.photoData, let image = Thumbnails.image(for: data, key: item.uuid) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: item.type.symbol)
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                    }
                }
                .frame(height: 96)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(Typography.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(Length.formatDimensions(
                        width: item.widthCm,
                        depth: item.depthCm,
                        height: item.heightCm,
                        system: unit
                    ))
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }

                // Always takes the same space, tags or not, so every card
                // in a row is the same height.
                HStack(spacing: 6) {
                    if let rooms = item.roomSummary { Tag(text: rooms) }
                    if item.isEstimated { Tag(text: "Estimated") }
                    if item.isFixed { Tag(text: "Fixed") }
                }
                .lineLimit(1)
                .frame(height: 22, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Small, ready-to-draw copies of item photos, kept in memory, so the grid
/// doesn't decode a full-size photo for every card while scrolling.
enum Thumbnails {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    static func image(for data: Data, key: UUID, maxSide: CGFloat = 400) -> UIImage? {
        // The data size is part of the key, so a new photo replaces the old.
        let cacheKey = "\(key.uuidString)-\(data.count)" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        let thumbnail = image.preparingThumbnail(of: fittedSize(image.size, maxSide: maxSide)) ?? image
        cache.setObject(thumbnail, forKey: cacheKey)
        return thumbnail
    }

    private static func fittedSize(_ size: CGSize, maxSide: CGFloat) -> CGSize {
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
