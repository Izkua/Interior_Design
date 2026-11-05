import UIKit

/// Hides the reference card in the photo that gets saved with an item.
///
/// People may measure with any wallet-size card, so the saved photo never
/// keeps it readable: the card's area (plus a margin) is pixelated. The
/// original photo is only kept in memory while measuring.
enum CardBlur {
    /// The area to hide: the box around the card's corners, grown by a
    /// margin so a slightly off tap still covers the whole card.
    static func region(corners: [CGPoint], imageSize: CGSize, margin: CGFloat = 0.35) -> CGRect? {
        guard corners.count >= 2, let minX = corners.map(\.x).min(), let maxX = corners.map(\.x).max(),
              let minY = corners.map(\.y).min(), let maxY = corners.map(\.y).max() else { return nil }
        var box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let grow = max(box.width, box.height) * margin + 12
        box = box.insetBy(dx: -grow, dy: -grow)
        let clipped = box.intersection(CGRect(origin: .zero, size: imageSize))
        return clipped.isNull || clipped.isEmpty ? nil : clipped
    }

    /// A copy of the photo with the card's area pixelated so nothing on it
    /// can be read. `corners` are in the image's own coordinates (points).
    static func hidingCard(in image: UIImage, corners: [CGPoint]) -> UIImage {
        guard let rect = region(corners: corners, imageSize: image.size) else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale

        // The area shrunk to a handful of blocks...
        let blocks = CGSize(width: max((rect.width / 20).rounded(), 1), height: max((rect.height / 20).rounded(), 1))
        let tinyFormat = UIGraphicsImageRendererFormat()
        tinyFormat.scale = 1
        let tiny = UIGraphicsImageRenderer(size: blocks, format: tinyFormat).image { _ in
            let scaleX = blocks.width / rect.width, scaleY = blocks.height / rect.height
            image.draw(in: CGRect(x: -rect.minX * scaleX, y: -rect.minY * scaleY,
                                  width: image.size.width * scaleX, height: image.size.height * scaleY))
        }
        // ...stretched back without smoothing: big flat squares that hide
        // any text or numbers.
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(at: .zero)
            context.cgContext.interpolationQuality = .none
            tiny.draw(in: rect)
        }
    }
}
