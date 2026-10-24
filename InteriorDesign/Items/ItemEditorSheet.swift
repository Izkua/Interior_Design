import SwiftUI
import SwiftData
import PhotosUI
import UIKit

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
            .onChange(of: photoSelection) { _, selection in
                loadPhoto(selection)
            }
        }
        .presentationDragIndicator(.visible)
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
                HStack {
                    Text("Room")
                        .font(Typography.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Picker("Room", selection: $draft.room) {
                        Text("No room").tag(Room?.none)
                        ForEach(rooms) { room in
                            Text(room.name).tag(Optional(room))
                        }
                    }
                    .tint(Theme.accent)
                }
                .frame(minHeight: Theme.minTap)

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
