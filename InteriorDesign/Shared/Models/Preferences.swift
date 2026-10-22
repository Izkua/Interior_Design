import Foundation
import SwiftData

/// A budget for one kind of item, for example "sofa: $800".
struct ItemBudget: Codable, Hashable {
    var type: ItemType
    var amount: Double
}

/// Shopping preferences for one room. Used by the catalog in a later week.
@Model
final class Preferences {
    var totalBudget: Double?
    var perItemBudgets: [ItemBudget]
    var styles: [String]
    var materials: [String]
    var minimumRating: Double
    var room: Room?

    init(
        totalBudget: Double? = nil,
        perItemBudgets: [ItemBudget] = [],
        styles: [String] = [],
        materials: [String] = [],
        minimumRating: Double = 4.0
    ) {
        self.totalBudget = totalBudget
        self.perItemBudgets = perItemBudgets
        self.styles = styles
        self.materials = materials
        self.minimumRating = minimumRating
    }
}
