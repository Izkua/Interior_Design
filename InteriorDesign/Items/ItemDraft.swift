import Foundation

/// The add/edit item form's values, kept apart from the saved `Item` so
/// Cancel can throw them away. The rules live here, not in the view, so
/// they can be unit-tested.
struct ItemDraft {
    var type: ItemType
    var name: String
    /// Sizes in centimeters.
    var widthCm: Double
    var depthCm: Double
    var heightCm: Double
    var notes = ""
    var isFixed = false
    var photoData: Data?
    var room: Room?

    /// A new item of `type`, starting at that type's usual size.
    init(type: ItemType = .sofa, room: Room? = nil) {
        let size = type.defaultSize
        self.type = type
        self.name = type.displayName
        self.widthCm = size.width
        self.depthCm = size.depth
        self.heightCm = size.height
        self.room = room
    }

    /// The values of an item that already exists, for editing.
    init(item: Item) {
        type = item.type
        name = item.name
        widthCm = item.widthCm
        depthCm = item.depthCm
        heightCm = item.heightCm
        notes = item.notes
        isFixed = item.isFixed
        photoData = item.photoData
        room = item.room
    }

    /// Switches the type. The size and name follow the new type only if
    /// the person had not changed them yet, so picking "Desk" after typing
    /// a size never throws that size away.
    mutating func setType(_ newType: ItemType) {
        let old = type.defaultSize
        let sizeUntouched = widthCm == old.width && depthCm == old.depth && heightCm == old.height
        let nameUntouched = trimmedName.isEmpty || trimmedName == type.displayName

        type = newType
        if sizeUntouched {
            let size = newType.defaultSize
            widthCm = size.width
            depthCm = size.depth
            heightCm = size.height
        }
        if nameUntouched {
            name = newType.displayName
        }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A new item from the form. Sizes typed by hand count as confirmed,
    /// so it is not marked estimated.
    func makeItem() -> Item {
        let item = Item(type: type)
        apply(to: item)
        return item
    }

    /// Copies the form into an existing item. Saving the form confirms the
    /// sizes, so an "Estimated" label goes away.
    func apply(to item: Item) {
        item.type = type
        item.name = trimmedName.isEmpty ? type.displayName : trimmedName
        item.widthCm = widthCm
        item.depthCm = depthCm
        item.heightCm = heightCm
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        item.isFixed = isFixed
        item.photoData = photoData
        item.room = room
        item.isEstimated = false
    }
}
