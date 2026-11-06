import UIKit

/// One piece to stand in the room in AR: its true size and the colors to
/// paint it. Made from a saved item or a catalog product.
struct ARPiece: Identifiable, Equatable {
    /// Each placed copy gets its own id, so the same item can be placed twice.
    var id = UUID()
    var name: String
    var type: ItemType
    var widthCm: Double
    var depthCm: Double
    var heightCm: Double
    var colors: FurnitureColors
    /// True while the size is a guess from a photo.
    var isEstimated = false
    /// Where to fetch a better color from later (catalog photos).
    var imageURL: URL?

    var parts: [FurnitureShape.Part] {
        FurnitureShape.parts(type: type, widthCm: widthCm, depthCm: depthCm, heightCm: heightCm)
    }
}

extension ARPiece {
    /// A saved item. The photo's colors are worked out here, so call this
    /// off the main thread for many items.
    init(item: Item) {
        self.init(
            name: item.name, type: item.type,
            widthCm: item.widthCm, depthCm: item.depthCm, heightCm: item.heightCm,
            colors: item.photoData.flatMap(UIImage.init(data:)).map { PhotoColors.colors(from: $0, type: item.type) }
                ?? .fallback(for: item.type),
            isEstimated: item.isEstimated
        )
    }

    /// A catalog product, or nil if the retailer lists no size (it can't be
    /// shown true to size). Colors start from the product's color names;
    /// the photo is checked once it downloads.
    init?(product: CatalogProduct) {
        guard product.hasDimensions, let w = product.widthCm, let d = product.depthCm, let h = product.heightCm else { return nil }
        let type = product.type ?? .other
        self.init(
            name: product.name, type: type, widthCm: w, depthCm: d, heightCm: h,
            colors: PhotoColors.colors(named: product.colors, type: type),
            imageURL: product.imageURL
        )
    }

    /// Downloads the product photo and picks colors from it. Nil if it
    /// can't be fetched.
    static func colors(fromImageAt url: URL, type: ItemType) async -> FurnitureColors? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
              let image = UIImage(data: data) else { return nil }
        return PhotoColors.colors(from: image, type: type)
    }
}
