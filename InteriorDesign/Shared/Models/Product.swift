import Foundation
import SwiftData

/// A product the person saved to their wishlist. Search results are plain
/// `CatalogProduct` values; only saved ones are stored here.
@Model
final class Product {
    var uuid: UUID
    /// The catalog's own ID, so saving the same product twice is noticed.
    var externalID: String = ""
    var name: String
    var price: Double
    var currencyCode: String
    /// Sizes in centimeters. Nil when the retailer does not list them, in
    /// which case the product is never marked as "fits your room".
    var widthCm: Double?
    var depthCm: Double?
    var heightCm: Double?
    var typeRaw: String?
    var materials: [String]
    var styles: [String] = []
    var colors: [String] = []
    var rating: Double?
    var reviewCount: Int?
    var imageURL: String?
    var retailer: String
    var linkURL: String
    var isSample: Bool = false
    var fetchedAt: Date

    init(
        name: String,
        price: Double,
        currencyCode: String = "USD",
        widthCm: Double? = nil,
        depthCm: Double? = nil,
        heightCm: Double? = nil,
        materials: [String] = [],
        rating: Double? = nil,
        reviewCount: Int? = nil,
        imageURL: String? = nil,
        retailer: String,
        linkURL: String
    ) {
        self.uuid = UUID()
        self.name = name
        self.price = price
        self.currencyCode = currencyCode
        self.widthCm = widthCm
        self.depthCm = depthCm
        self.heightCm = heightCm
        self.materials = materials
        self.rating = rating
        self.reviewCount = reviewCount
        self.imageURL = imageURL
        self.retailer = retailer
        self.linkURL = linkURL
        self.fetchedAt = Date()
    }

    /// Saves a search result.
    convenience init(_ product: CatalogProduct) {
        self.init(
            name: product.name,
            price: product.price,
            currencyCode: product.currency,
            widthCm: product.widthCm,
            depthCm: product.depthCm,
            heightCm: product.heightCm,
            materials: product.materials,
            rating: product.rating,
            reviewCount: product.reviewCount,
            imageURL: product.imageURL?.absoluteString,
            retailer: product.retailer,
            linkURL: product.url?.absoluteString ?? ""
        )
        externalID = product.id
        typeRaw = product.type?.rawValue
        styles = product.styles
        colors = product.colors
        isSample = product.isSample
    }

    /// Back to the plain value the catalog screens use.
    var catalogProduct: CatalogProduct {
        CatalogProduct(
            id: externalID.isEmpty ? uuid.uuidString : externalID,
            name: name,
            price: price,
            currency: currencyCode,
            widthCm: widthCm,
            depthCm: depthCm,
            heightCm: heightCm,
            type: typeRaw.flatMap(ItemType.init(rawValue:)),
            materials: materials,
            styles: styles,
            colors: colors,
            rating: rating,
            reviewCount: reviewCount,
            imageURL: imageURL.flatMap(URL.init(string:)),
            retailer: retailer,
            url: linkURL.isEmpty ? nil : URL(string: linkURL),
            isSample: isSample
        )
    }
}
