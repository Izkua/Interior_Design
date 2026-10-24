import Foundation

/// Whether a product fits the room, and why not.
enum FitResult: Equatable, Sendable {
    /// There is a spot that keeps every rule (doors, windows, walking path).
    case fits(ItemPlacement)
    /// No size listed, so we can't say. Never shown as fitting.
    case unknownSize
    case doesNotFit(reason: String)

    var fits: Bool {
        if case .fits = self { return true }
        return false
    }
}

/// Checks a product against the free floor in a room, using the same
/// rules and spot-finding as the layout engine. Furniture already in the
/// room stays where it is in the chosen layout.
enum FitCheck {
    static func check(_ product: CatalogProduct, room: LayoutRoom, furniture: [PlacedItem]) -> FitResult {
        guard let item = product.asLayoutItem() else { return .unknownSize }
        let rules = LayoutRules(room: room)

        if let spot = LayoutEngine.findSpot(for: item, among: furniture, rules: rules) {
            return .fits(spot.placement)
        }

        // Explain why, from the simplest reason to the most specific.
        let xs = room.corners.map(\.x), ys = room.corners.map(\.y)
        let roomW = (xs.max() ?? 0) - (xs.min() ?? 0)
        let roomL = (ys.max() ?? 0) - (ys.min() ?? 0)
        let fitsOutline = (item.width <= roomW && item.depth <= roomL) || (item.width <= roomL && item.depth <= roomW)
        if !fitsOutline {
            return .doesNotFit(reason: "It's bigger than the room.")
        }
        if LayoutEngine.findSpot(for: item, among: [], rules: rules) == nil {
            return .doesNotFit(reason: "It doesn't fit with room to walk around it, even in the empty room.")
        }
        return .doesNotFit(reason: "There isn't a free spot big enough next to your furniture without blocking a door or walkway.")
    }
}
