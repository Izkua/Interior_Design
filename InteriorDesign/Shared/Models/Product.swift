import Foundation
import SwiftData

/// A product from the catalog, cached on the device. Filled in by the
/// catalog work in a later week.
@Model
final class Product {
    var uuid: UUID
    var name: String
    var price: Double
    var currencyCode: String
    /// Sizes in centimeters. Nil when the retailer does not list them, in
    /// which case the product is never marked as "fits your room".
    var widthCm: Double?
    var depthCm: Double?
    var heightCm: Double?
    var materials: [String]
    var rating: Double?
    var reviewCount: Int?
    var imageURL: String?
    var retailer: String
    var linkURL: String
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
}
