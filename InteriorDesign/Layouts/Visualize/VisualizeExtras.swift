import SwiftUI
import UIKit

/// The extra pictures sent with a Visualize request, so the AI image shows
/// this layout and these pieces: a top-down plan, and photos of the
/// person's own furniture.
enum VisualizeExtras {
    /// The layout's floor plan as a PNG (base64), the same drawing the app
    /// shows, with each piece labeled.
    @MainActor
    static func planImage(room: Room, placements: [ItemPlacement], items: [LayoutItem]) -> String? {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let placed = placements.compactMap { p in byID[p.itemID].map { PlacedItem(item: $0, placement: p) } }
        guard !placed.isEmpty else { return nil }
        let plan = LayoutPlanView(room: room.layoutRoom, placed: placed, unit: UnitSystem.deviceDefault)
            .frame(width: 512, height: 512)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: plan)
        renderer.scale = 1
        return renderer.uiImage?.pngData()?.base64EncodedString()
    }

    /// Photos (the chosen cutout, else the photo) of up to `limit` placed
    /// pieces, biggest first, at most 512 px.
    @MainActor
    static func piecePhotos(room: Room, placements: [ItemPlacement], items: [LayoutItem], limit: Int = 4) -> [VisualizeRequest.PiecePhoto] {
        let placedIDs = Set(placements.map(\.itemID))
        let byID = Dictionary(room.allItems.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        let candidates = items
            .filter { placedIDs.contains($0.id) }
            .sorted { $0.width * $0.depth > $1.width * $1.depth }
        var result: [VisualizeRequest.PiecePhoto] = []
        for layoutItem in candidates where result.count < limit {
            guard let item = byID[layoutItem.id] else { continue }
            if let cutout = item.cutoutData, let small = shrink(cutout, png: true) {
                result.append(.init(name: item.name, data: small, mime: "image/png"))
            } else if let photo = item.photoData, let small = shrink(photo, png: false) {
                result.append(.init(name: item.name, data: small, mime: "image/jpeg"))
            }
        }
        return result
    }

    /// A smaller copy, base64: PNG keeps a cutout's see-through background.
    private static func shrink(_ data: Data, png: Bool, maxSide: CGFloat = 512) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !png
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return (png ? small.pngData() : small.jpegData(compressionQuality: 0.75))?.base64EncodedString()
    }
}
