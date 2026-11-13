import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import simd

/// Add a piece of furniture by hand, or edit one. Pass an item to edit it;
/// pass nil to add a new one.
struct ItemEditorSheet: View {
    let item: Item?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \Room.updatedAt, order: .reverse) private var rooms: [Room]

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue

    @State private var draft: ItemDraft
    @State private var photoSelection: PhotosPickerItem?
    @State private var confirmDelete = false
    @State private var showAR = false
    /// The values when the screen opened, to tell if anything changed.
    @State private var original: ItemDraft
    /// Saved or deleted already, so closing doesn't save again.
    @State private var didFinish = false
    /// A new item that was kept early because it got an AI model.
    @State private var createdItem: Item?

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    /// From a small stool leg to a large sectional, in centimeters.
    private let sizeRange: ClosedRange<Double> = 0.5...1000

    init(item: Item?, defaultRoom: Room? = nil) {
        self.item = item
        let start = item.map(ItemDraft.init(item:)) ?? ItemDraft(room: defaultRoom)
        _draft = State(initialValue: start)
        _original = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    photoCard
                    typeCard
                    sizeCard
                    detailsCard
                    Model3DSection(
                        name: draft.type.displayName,
                        photoData: draft.photoData,
                        cutoutData: $draft.cutoutData,
                        modelData: $draft.modelData,
                        cutoutSource: $draft.cutoutSource,
                        allowScan: true,
                        onScanned: useScan,
                        onNewModel: { _ in saveModelNow() },
                        isPaused: showAR
                    ) {
                        hideKeyboard()
                        showAR = true
                    }
                    if item != nil {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete item", systemImage: "trash")
                                .font(Typography.headline)
                                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                        }
                        .foregroundStyle(Theme.danger)
                    }
                }
                .padding(Theme.Space.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(item == nil ? "Add item" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if item == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                            .frame(minHeight: Theme.minTap)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save", action: save)
                            .fontWeight(.semibold)
                            .frame(minHeight: Theme.minTap)
                    }
                } else {
                    // Changes to an existing item save by themselves.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                            .frame(minHeight: Theme.minTap)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
            .confirmationDialog("Delete \(draft.trimmedName.isEmpty ? "this item" : draft.trimmedName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete item", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
            .fullScreenCover(isPresented: $showAR) {
                ARPlaceView(start: [arPiece])
            }
            .onDisappear(perform: autosave)
            .onChange(of: draft.cutoutData) { _, _ in saveModelNow() }
            .onChange(of: draft.modelData) { _, _ in saveModelNow() }
            .onChange(of: photoSelection) { _, selection in
                loadPhoto(selection)
            }
        }
        .presentationDragIndicator(.visible)
    }

    /// The piece as it is in the form now, unsaved changes included.
    private var arPiece: ARPiece {
        ARPiece(
            name: draft.trimmedName.isEmpty ? draft.type.displayName : draft.trimmedName,
            type: draft.type, widthCm: draft.widthCm, depthCm: draft.depthCm, heightCm: draft.heightCm,
            colors: draft.photoData.flatMap(UIImage.init(data:)).map { PhotoColors.colors(from: $0, type: draft.type) }
                ?? .fallback(for: draft.type),
            isEstimated: item?.isEstimated ?? false,
            photoData: draft.photoData,
            modelData: draft.modelData,
            cutoutData: draft.cutoutData
        )
    }

    // MARK: 3D model

    /// A LiDAR scan is true to size, so it also measures the piece.
    private func useScan(_ data: Data) {
        draft.useScannedSize(data)
    }

    // MARK: Photo

    private var photoCard: some View {
        AppCard {
            HStack(spacing: Theme.Space.md) {
                ZStack {
                    Theme.surfaceAlt
                    if let data = draft.photoData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: draft.type.symbol)
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    // The photo picker runs outside the app, so it needs no
                    // photo library permission.
                    PhotosPicker(selection: $photoSelection, matching: .images) {
                        Label(draft.photoData == nil ? "Add photo" : "Change photo", systemImage: "photo")
                            .font(Typography.subheadline)
                            .frame(minHeight: Theme.minTap)
                    }
                    if draft.photoData != nil {
                        Button("Remove photo", role: .destructive) {
                            draft.photoData = nil
                            photoSelection = nil
                        }
                        .font(Typography.subheadline)
                        .frame(minHeight: Theme.minTap)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func loadPhoto(_ selection: PhotosPickerItem?) {
        guard let selection else { return }
        Task {
            guard let data = try? await selection.loadTransferable(type: Data.self) else { return }
            draft.photoData = PhotoResizer.jpeg(from: data)
        }
    }

    // MARK: Type

    private var typeCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                SectionHeader(title: "What is it?")
                ItemTypePicker(selection: Binding(get: { draft.type }, set: { if let type = $0 { draft.setType(type) } }))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                    TextField(draft.type.displayName, text: $draft.name)
                        .font(Typography.headline)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .background(
                            Theme.surfaceAlt,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        )
                }
            }
        }
    }

    // MARK: Size

    private var sizeCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                HStack {
                    SectionHeader(title: "Size")
                    if item?.isEstimated == true { Tag(text: "Estimated") }
                }
                if item?.isEstimated == true {
                    Text("These sizes are a guess. Check them with a tape measure, then Save to confirm.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(unit == .imperial
                     ? "In inches unless you type feet, like 6′ 2″."
                     : "In centimeters unless you type meters, like 1.8 m.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(alignment: .top, spacing: Theme.Space.sm) {
                    LengthField(title: "Width", cm: $draft.widthCm, unit: unit, range: sizeRange, scale: .furniture)
                    LengthField(title: "Depth", cm: $draft.depthCm, unit: unit, range: sizeRange, scale: .furniture)
                    LengthField(title: "Height", cm: $draft.heightCm, unit: unit, range: sizeRange, scale: .furniture)
                }
            }
        }
    }

    // MARK: Room, fixed, notes

    private var detailsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                RoomChooser(rooms: $draft.rooms, anyRoom: $draft.anyRoom, allRooms: rooms)

                if LightWarmth.isLight(draft.type) {
                    LightWarmthPicker(title: "Light color", selection: $draft.lightWarmth,
                                      help: "Check the bulb or its box: 2700 K is warm, 5000 K is cool. Used to suggest lamps that match.")
                }

                Toggle(isOn: $draft.isFixed) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fixed in place")
                            .font(Typography.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Like a built-in wardrobe. Layouts won't move it.")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .tint(Theme.accent)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                    TextField("Optional, like color or where it came from", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...5)
                        .padding(12)
                        .background(
                            Theme.surfaceAlt,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        )
                }
            }
        }
    }

    // MARK: Save and delete

    /// Saves an existing item's changes when the screen closes, however it
    /// closes (Done, or swiping down). A new item that already has an AI
    /// model is kept too, since that model cost a credit.
    private func autosave() {
        guard !didFinish else { return }
        if let target = item ?? createdItem {
            guard draft != original else { return }
            draft.apply(to: target)
            original = draft
            try? context.save()
        } else if draft.modelData.map(GLBModel.isGLB) == true {
            let newItem = draft.makeItem()
            context.insert(newItem)
            createdItem = newItem
            original = draft
            try? context.save()
        }
    }

    /// A new 3D model or cutout is saved to an existing item right away,
    /// without touching anything else.
    private func saveModelNow() {
        guard let item else { return }
        item.modelData = draft.modelData
        item.cutoutData = draft.cutoutData
        item.cutoutSource = draft.cutoutSource
        try? context.save()
    }

    private func save() {
        hideKeyboard()
        didFinish = true
        if let target = item ?? createdItem {
            draft.apply(to: target)
        } else {
            context.insert(draft.makeItem())
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        guard let item else { return }
        didFinish = true
        context.delete(item)
        try? context.save()
        dismiss()
    }
}

/// Shrinks a picked photo before saving, so a 12-megapixel picture does
/// not fill up the phone's storage.
enum PhotoResizer {
    static func jpeg(from data: Data, maxSide: CGFloat = 1200, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

extension ItemDraft {
    /// A LiDAR scan is true to size, so it also measures the piece. Width
    /// and depth follow whichever way round matches the current guess.
    /// Returns false if the model's size couldn't be read.
    @MainActor @discardableResult
    mutating func useScannedSize(_ data: Data) -> Bool {
        guard let size = ARPlaceController.modelSize(data) else { return false }
        let target = simd_float3(Float(widthCm), Float(heightCm), Float(depthCm)) / 100
        let turned = ModelFit.fit(extents: size, target: target).turned
        widthCm = Double((turned ? size.z : size.x) * 100).rounded()
        depthCm = Double((turned ? size.x : size.z) * 100).rounded()
        heightCm = Double(size.y * 100).rounded()
        return true
    }
}
