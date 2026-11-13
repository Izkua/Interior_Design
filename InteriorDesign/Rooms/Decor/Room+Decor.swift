import Foundation
import SwiftData
import UIKit

/// Turning the room's decor into plain values for the decor planners, and
/// saving the person's choice back.
extension Room {
    func items(in category: ItemCategory) -> [Item] {
        allItems.filter { $0.type.category == category }
    }

    // MARK: Wall decor

    /// Gives every hung piece an entry in Current Items, so wall decor shows
    /// up there too. TVs are skipped. Safe to call often.
    @MainActor
    func linkDecorItems() {
        guard let context = modelContext else { return }
        var changed = false
        for index in wallDecor.indices where wallDecor[index].itemID == nil {
            let piece = wallDecor[index]
            guard piece.kind != .tv else { continue }
            let item = Item(type: piece.kind.itemType, name: piece.name, widthCm: piece.widthCm,
                            depthCm: piece.depthCm, heightCm: piece.heightCm)
            context.insert(item)
            item.setRooms([self], anyRoom: false)
            wallDecor[index].itemID = item.uuid
            changed = true
        }
        if changed { try? context.save() }
    }

    /// Owned wall decor in this room that isn't on a wall yet.
    var unhungWallDecor: [Item] {
        let hung = Set(wallDecor.compactMap(\.itemID))
        return items(in: .wallDecor).filter { !hung.contains($0.uuid) }
    }

    /// Hangs an owned piece on a wall, at its own size.
    @discardableResult
    func hang(_ item: Item, onWall wall: Int) -> WallDecor {
        let kind = item.type.decorKind ?? .frame
        var piece = addDecor(kind, wall: wall)
        updateDecor(id: piece.id) {
            $0.name = item.name
            $0.widthCm = item.widthCm
            $0.heightCm = item.heightCm
            $0.depthCm = max(item.depthCm, 1)
            $0.itemID = item.uuid
        }
        piece = wallDecor.first { $0.id == piece.id } ?? piece
        return piece
    }

    /// Everything the wall planner should arrange: what's hung, plus owned
    /// wall decor not hung yet (starting on the first wall).
    var wallDecorForPlanning: [WallDecor] {
        wallDecor + unhungWallDecor.map { item in
            var piece = WallDecor(kind: item.type.decorKind ?? .frame, name: item.name, wall: 0, centerX: 0,
                                  widthCm: item.widthCm, heightCm: item.heightCm, depthCm: max(item.depthCm, 1), itemID: item.uuid)
            // The same id every time (the item's), so screens that watch
            // this list don't see a "new" piece on every redraw and redo
            // their work forever (that froze the Layouts page).
            piece.id = item.uuid
            return piece
        }
    }

    /// The room's walls for the planner, with the furniture standing in
    /// front of each (from `placed`).
    func plannerWalls(placed: [PlacedItem]) -> [PlannerWall] {
        let boxes = placed.map { p in
            let box = p.footprint
            return WallDecorGeometry.FloorBox(id: p.item.id, name: p.item.name, minX: box.minX, minY: box.minY,
                                              maxX: box.maxX, maxY: box.maxY, height: p.item.height)
        }
        let types = Dictionary(placed.map { ($0.item.id, $0.item.type) }, uniquingKeysWith: { a, _ in a })
        return corners.indices.map { wall in
            PlannerWall(
                index: wall,
                name: PlanGeometry.wallName(wall, cornerCount: corners.count),
                length: wallLength(wall),
                blocked: features(onWall: wall).filter { $0.kind != .outlet }
                    .map { WallDecorGeometry.rect(for: $0, ceiling: ceilingHeightCm) },
                furniture: WallDecorGeometry.furnitureAgainst(wall: wall, corners: corners, boxes: boxes),
                furnitureTypes: types
            )
        }
    }

    /// Replaces the room's wall decor with a suggestion.
    func applyWallDecor(_ decor: [WallDecor]) {
        wallDecor = decor.map { WallDecorGeometry.clamped($0, wallLength: wallLength($0.wall), ceiling: ceilingHeightCm) }
        updatedAt = Date()
    }

    // MARK: Small decor

    @MainActor
    var smallDecorPieces: [DecorPiece] {
        items(in: .smallDecor).map { item in
            item.refreshColor()
            return DecorPiece(id: item.uuid, type: item.type, name: item.name, width: item.widthCm,
                              depth: item.depthCm, height: item.heightCm, color: item.mainColor)
        }
    }

    var decorSurfaces: [DecorSurface] {
        furnitureItems.filter(\.type.hasSurface).map {
            DecorSurface(id: $0.uuid, type: $0.type, name: $0.name, width: $0.widthCm, depth: $0.depthCm, height: $0.heightCm)
        }
    }

    func applySurfaceDecor(_ spots: [SurfaceSpot]) {
        surfaceDecor = spots
        updatedAt = Date()
    }

    /// Changes whenever anything the decor planners look at changes.
    var decorSignature: String {
        let walls = wallDecorForPlanning.map { "\($0.id):\(Int($0.widthCm))x\(Int($0.heightCm)):\($0.colors.joined())" }.joined(separator: ";")
        let small = items(in: .smallDecor).map { "\($0.uuid):\(Int($0.widthCm))x\(Int($0.depthCm))x\(Int($0.heightCm))" }.joined(separator: ";")
        return [layoutSignature, walls, small, "\(Int(ceilingHeightCm))"].joined(separator: "|")
    }
}

// MARK: - Photos and colors of wall decor


extension Room {
    /// Changes when a hung piece's photo changes.
    var decorPhotoKey: String {
        let items = Dictionary(self.items(in: .wallDecor).map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        return wallDecor.map { piece in
            "\(piece.id):\(piece.itemID.flatMap { items[$0]?.photoData?.count } ?? 0)"
        }.joined(separator: ";")
    }

    /// Small copies of the photos of hung pieces, by piece id.
    @MainActor
    func decorPhotos() -> [UUID: UIImage] {
        let items = Dictionary(self.items(in: .wallDecor).map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        var result: [UUID: UIImage] = [:]
        for piece in wallDecor {
            guard let item = piece.itemID.flatMap({ items[$0] }), let data = item.photoData,
                  let image = UIImage(data: data) else { continue }
            result[piece.id] = image.preparingThumbnail(of: CGSize(width: 300, height: 300 * image.size.height / max(image.size.width, 1))) ?? image
        }
        return result
    }

    /// Puts a photo on a hung piece (and its Current Items entry) and reads
    /// its main colors from it.
    @MainActor
    func setDecorPhoto(_ data: Data, for pieceID: UUID) {
        linkDecorItems()
        guard let piece = wallDecor.first(where: { $0.id == pieceID }),
              let itemID = piece.itemID, let item = allItems.first(where: { $0.uuid == itemID }),
              let jpeg = PhotoResizer.jpeg(from: data), let image = UIImage(data: jpeg) else { return }
        item.photoData = jpeg
        let palette = PhotoColors.palette(from: image, count: 3)
        updateDecor(id: pieceID) { $0.colors = palette.map(\.hex) }
        try? modelContext?.save()
    }

    /// The photo of a hung piece, if it has one.
    func decorPhoto(for pieceID: UUID) -> Data? {
        guard let itemID = wallDecor.first(where: { $0.id == pieceID })?.itemID else { return nil }
        return allItems.first { $0.uuid == itemID }?.photoData
    }
}

/// Colors a person can tap to say what a piece looks like.
enum DecorColorOption {
    static let all: [(name: String, hex: String)] = [
        ("White", "#F2F0EB"), ("Black", "#1C1C1C"), ("Grey", "#8A8A8A"), ("Beige", "#D8C3A5"),
        ("Brown", "#7B5235"), ("Green", "#4A7A55"), ("Blue", "#3C5A96"), ("Red", "#B23A3A"),
        ("Pink", "#E3A1B4"), ("Orange", "#E08A3C"), ("Yellow", "#E6C94F"), ("Purple", "#7B5BA6"),
    ]
}
