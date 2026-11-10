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
    /// The piece's own photo (saved items).
    var photoData: Data?
    /// Where to fetch its photo from (catalog products).
    var imageURL: URL?
    /// A real 3D model of it (USDZ), if the person scanned or imported one.
    var modelData: Data?
    /// The piece cut out of its photo (PNG), as the person chose it.
    var cutoutData: Data?
    /// The catalog product's id, so an AI 3D model can be made of it.
    var productID: String?
    /// The catalog product itself, for the saved 3D models list.
    var product: CatalogProduct?

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
            isEstimated: item.isEstimated,
            photoData: item.photoData,
            modelData: item.modelData,
            cutoutData: item.cutoutData
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
            imageURL: product.imageURL,
            product: product
        )
    }

    /// True when the 3D model is an AI-made GLB (not a scan or import).
    var hasAIModel: Bool { modelData.map(GLBModel.isGLB) ?? false }

    /// The piece's photo: the saved one, or the product photo downloaded.
    /// Nil if there's none or it can't be fetched.
    func loadPhoto() async -> UIImage? {
        if let photoData, let image = UIImage(data: photoData) { return image }
        guard let url = imageURL,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { return nil }
        return UIImage(data: data)
    }
}
