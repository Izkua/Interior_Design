import Foundation
import Observation

/// The catalog products this phone has an AI 3D model of, newest first,
/// for the Catalog's "3D models" button. The list and the model files are
/// kept on the phone (Application Support), so they stay until removed.
@MainActor
@Observable
final class SavedModels {
    static let shared = SavedModels()

    struct Entry: Codable, Identifiable, Hashable {
        var product: CatalogProduct
        var savedAt: Date
        var id: String { product.id }
    }

    private(set) var entries: [Entry] = []

    init(folder: URL? = SavedModels.defaultFolder) {
        self.folder = folder
        if let file = indexFile, let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    /// Adds (or moves to the top) a product whose model was just shown.
    func remember(_ product: CatalogProduct) {
        entries.removeAll { $0.id == product.id }
        entries.insert(Entry(product: product, savedAt: Date()), at: 0)
        save()
    }

    /// Takes a product off the list and deletes its model file from the
    /// phone. (It's still saved on the server, so opening the product
    /// again brings it back for free.)
    func remove(_ productID: String) {
        entries.removeAll { $0.id == productID }
        if let file = modelFile(productID) { try? FileManager.default.removeItem(at: file) }
        save()
    }

    /// The saved model of a product, if this phone has one.
    func model(_ productID: String) -> Data? {
        modelFile(productID).flatMap { try? Data(contentsOf: $0) }
    }

    /// Saves a product's model and puts it at the top of the list.
    func save(model data: Data, for product: CatalogProduct) {
        guard let folder, let file = modelFile(product.id) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        remember(product)
    }

    /// The cutout the person chose for a product (PNG), if any.
    func cutout(_ productID: String) -> Data? {
        cutoutFile(productID).flatMap { try? Data(contentsOf: $0) }
    }

    func setCutout(_ png: Data?, for productID: String) {
        guard let folder, let file = cutoutFile(productID) else { return }
        if let png {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? png.write(to: file, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func cutoutFile(_ productID: String) -> URL? {
        modelFile(productID)?.deletingPathExtension().appendingPathExtension("cutout.png")
    }

    /// Where a product's GLB file is kept.
    func modelFile(_ productID: String) -> URL? {
        guard productID.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil, let folder else { return nil }
        return folder.appendingPathComponent("\(productID).glb")
    }

    // MARK: Storage

    private let folder: URL?
    private var indexFile: URL? { folder?.appendingPathComponent("index.json") }

    nonisolated static var defaultFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ProductModels", isDirectory: true)
    }

    private func save() {
        guard let folder, let file = indexFile, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
