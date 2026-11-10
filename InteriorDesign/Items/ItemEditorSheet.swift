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
    @State private var showScan = false
    @State private var showImport = false
    @State private var showCutout = false
    @State private var isMakingModel = false
    /// A short note under the 3D model card, like "Sizes updated from the scan."
    @State private var modelNote: String?

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    /// From a small stool leg to a large sectional, in centimeters.
    private let sizeRange: ClosedRange<Double> = 0.5...1000

    init(item: Item?, defaultRoom: Room? = nil) {
        self.item = item
        _draft = State(initialValue: item.map(ItemDraft.init(item:)) ?? ItemDraft(room: defaultRoom))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    photoCard
                    typeCard
                    sizeCard
                    modelCard
                    if ARPlaceView.isAvailable {
                        Button {
                            hideKeyboard()
                            showAR = true
                        } label: {
                            Label("See it in my room", systemImage: "arkit")
                                .font(Typography.headline)
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityHint("Shows this piece at its true size in your room, through the camera")
                    }
                    detailsCard
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .frame(minHeight: Theme.minTap)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .frame(minHeight: Theme.minTap)
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
            .fullScreenCover(isPresented: $showScan) {
                #if !targetEnvironment(simulator)
                ObjectScanView { data in useScan(data) }
                #endif
            }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.usdz]) { result in
                importModel(result)
            }
            .fullScreenCover(isPresented: $showAR) {
                ARPlaceView(start: [arPiece])
            }
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

    private var modelCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                HStack {
                    SectionHeader(title: "3D model")
                    if draft.modelData != nil { Tag(text: "Added") }
                }
                Text(draft.modelData != nil
                     ? "\"See it in my room\" shows this 3D model."
                     : draft.photoData != nil
                        ? "Make an AI 3D model from the photo, using the cutout you choose. Your photo is sent to Stability AI to make it."
                        : (ObjectScan.isSupported
                           ? "Scan the piece in 3D by walking around it, or add a photo to make an AI 3D model."
                           : "Add a photo to make an AI 3D model, or import a 3D model (.usdz) made on another phone or a Mac."))
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let modelNote {
                    Text(modelNote)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textPrimary)
                }
                if let photo = draft.photoData.flatMap(UIImage.init(data:)) {
                    HStack(spacing: Theme.Space.sm) {
                        modelButton(draft.cutoutData == nil ? "Choose cutout" : "Change cutout", systemImage: "scissors") {
                            showCutout = true
                        }
                        modelButton(isMakingModel ? "Making…" : "Make AI 3D", systemImage: "wand.and.stars") {
                            Task { await makeAIModel(from: photo) }
                        }
                        .disabled(isMakingModel)
                    }
                    .sheet(isPresented: $showCutout) {
                        CutoutPickerView(photo: photo, itemName: draft.type.displayName) { png in
                            draft.cutoutData = png
                            modelNote = "Cutout chosen. Save to keep it."
                        }
                    }
                }
                HStack(spacing: Theme.Space.sm) {
                    if ObjectScan.isSupported {
                        modelButton(draft.modelData == nil ? "Scan in 3D" : "Scan again", systemImage: "cube.transparent") {
                            hideKeyboard()
                            showScan = true
                        }
                    }
                    modelButton(ObjectScan.isSupported ? "Import" : "Import 3D model", systemImage: "square.and.arrow.down") {
                        showImport = true
                    }
                }
                if draft.modelData != nil {
                    Button("Remove 3D model", role: .destructive) {
                        draft.modelData = nil
                        modelNote = nil
                    }
                    .font(Typography.subheadline)
                    .frame(minHeight: Theme.minTap)
                }
            }
        }
    }

    private func modelButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Typography.subheadline)
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    /// Sends the chosen cutout (or the photo, cut out automatically) to be
    /// made into an AI 3D model.
    private func makeAIModel(from photo: UIImage) async {
        isMakingModel = true
        defer { isMakingModel = false }
        modelNote = "Making the 3D model… this takes about a minute."
        var png = draft.cutoutData
        if png == nil, let auto = await PhotoCutout.cutout(from: photo) {
            png = UIImage(cgImage: auto).pngData()
        }
        guard let png = png ?? photo.jpegData(compressionQuality: 0.9) else {
            modelNote = "The photo couldn't be read."
            return
        }
        do {
            draft.modelData = try await ProductModelService.model(fromPhoto: png)
            modelNote = "AI-generated 3D model added. It's approximate. Save to keep it."
        } catch {
            modelNote = error.localizedDescription
        }
    }

    /// A LiDAR scan is true to size, so it also measures the piece.
    private func useScan(_ data: Data) {
        draft.modelData = data
        guard let size = ARPlaceController.modelSize(data) else {
            modelNote = "3D model added."
            return
        }
        let target = simd_float3(Float(draft.widthCm), Float(draft.heightCm), Float(draft.depthCm)) / 100
        let turned = ModelFit.fit(extents: size, target: target).turned
        draft.widthCm = Double((turned ? size.z : size.x) * 100).rounded()
        draft.depthCm = Double((turned ? size.x : size.z) * 100).rounded()
        draft.heightCm = Double(size.y * 100).rounded()
        modelNote = "3D model added. The sizes above were measured by the scan; Save to keep them."
    }

    private func importModel(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), ARPlaceController.modelSize(data) != nil else {
            modelNote = "That file couldn't be opened as a 3D model."
            return
        }
        draft.modelData = data
        modelNote = "3D model added. It's sized to fit the sizes above."
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
                            draft.photoData = nil; draft.cutoutData = nil
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
            draft.photoData = PhotoResizer.jpeg(from: data); draft.cutoutData = nil
        }
    }

    // MARK: Type

    private var typeCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                SectionHeader(title: "What is it?")
                FlowLayout(spacing: Theme.Space.sm) {
                    ForEach(ItemType.allCases) { type in
                        Chip(title: type.displayName, systemImage: type.symbol, isSelected: draft.type == type) {
                            draft.setType(type)
                        }
                    }
                }
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

    private func save() {
        hideKeyboard()
        if let item {
            draft.apply(to: item)
        } else {
            context.insert(draft.makeItem())
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        guard let item else { return }
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
