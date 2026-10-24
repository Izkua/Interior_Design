import SwiftUI
import PhotosUI
import Photos

/// Whether the Visualize button works right now, and if not, why.
enum VisualizeAvailability: Equatable {
    case ready
    /// In debug builds with demo mode on: made-up pictures.
    case demo
    case signInNeeded
    case comingSoon

    @MainActor
    static var current: VisualizeAvailability {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: SettingsKey.demoAIFeatures) { return .demo }
        #endif
        guard BackendConfig.visualizeEnabled else { return .comingSoon }
        return AuthStore.shared.isSignedIn ? .ready : .signInNeeded
    }

    var canOpen: Bool { self == .ready || self == .demo }

    var note: String {
        switch self {
        case .ready: return "Make an AI picture of this layout."
        case .demo: return "Demo mode: pictures are made up."
        case .signInNeeded: return "Sign in to make AI pictures of a layout."
        case .comingSoon: return "AI pictures of a layout are coming soon."
        }
    }
}

/// The Visualize button for a layout, with a note when it can't be used.
struct VisualizeButton: View {
    let room: Room
    let placements: [ItemPlacement]
    let items: [LayoutItem]
    var style: PrimaryButton.Style = .filled

    @State private var showSheet = false
    @AppStorage(SettingsKey.demoAIFeatures) private var demoMode = false
    @State private var auth = AuthStore.shared

    var body: some View {
        // Reading these makes the button update when they change.
        let _ = (demoMode, auth.isSignedIn)
        let availability = VisualizeAvailability.current
        VStack(spacing: Theme.Space.xs) {
            PrimaryButton(title: "Visualize", systemImage: "sparkles", style: style) { showSheet = true }
                .disabled(!availability.canOpen)
                .opacity(availability.canOpen ? 1 : 0.45)
            Text(availability.note)
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showSheet) {
            VisualizeSheet(room: room, placements: placements, items: items, demo: availability == .demo)
        }
    }
}

/// Pick a style, optionally add a photo of the room, and make a picture.
struct VisualizeSheet: View {
    let room: Room
    let placements: [ItemPlacement]
    let items: [LayoutItem]
    let demo: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthStore.shared
    @State private var style: VisualStyle = .scandinavian
    @State private var roomPhoto: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var result: UIImage?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var saveMessage: String?
    @State private var task: Task<Void, Never>?

    private var service: VisualizeService {
        #if DEBUG
        if demo { return DemoVisualizeService() }
        #endif
        return BackendVisualizeService(accessToken: { await AuthStore.shared.validAccessToken() })
    }

    /// True when today's or this month's pictures are used up.
    private var outOfPictures: Bool {
        guard !demo else { return false }
        return (auth.imagesToday ?? 0) >= AuthStore.imagesPerDay || (auth.imagesThisMonth ?? 0) >= AuthStore.imagesPerMonth
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    if let result {
                        resultView(result)
                    } else {
                        setup
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Theme.Space.md)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Visualize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isWorking ? "Stop" : "Close") {
                        task?.cancel()
                        dismiss()
                    }
                }
            }
            .task { await auth.loadUsage() }
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) { roomPhoto = UIImage(data: data) }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isWorking)
    }

    // MARK: Before

    private var setup: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            AppCard {
                VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                    SectionHeader(title: "Style")
                    FlowLayout(spacing: Theme.Space.sm) {
                        ForEach(VisualStyle.allCases) { option in
                            Chip(title: option.title, isSelected: style == option) { style = option }
                        }
                    }
                }
            }

            AppCard {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionHeader(title: "Photo of your room (optional)")
                    Text("With a photo, the picture can match your walls, floor, and light.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                    HStack {
                        if let roomPhoto {
                            Image(uiImage: roomPhoto).resizable().scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(roomPhoto == nil ? "Choose photo" : "Change photo", systemImage: "photo")
                                .font(Typography.subheadline)
                                .frame(minHeight: Theme.minTap)
                        }
                    }
                }
            }

            usageLine

            if isWorking {
                VStack(spacing: Theme.Space.sm) {
                    ProgressView()
                    Text("Making your picture. This can take up to a minute.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                PrimaryButton(title: "Make picture", systemImage: "sparkles", action: generate)
                    .disabled(outOfPictures)
                    .opacity(outOfPictures ? 0.45 : 1)
            }

            Text(AIImageLabel.text)
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var usageLine: some View {
        HStack {
            Label("Pictures", systemImage: "sparkles")
            Spacer()
            if demo {
                Text("Demo, not counted")
            } else {
                Text("\(auth.imagesToday ?? 0) of \(AuthStore.imagesPerDay) today · \(auth.imagesThisMonth ?? 0) of \(AuthStore.imagesPerMonth) this month")
            }
        }
        .font(Typography.caption)
        .foregroundStyle(Theme.textSecondary)
    }

    private func generate() {
        isWorking = true
        errorMessage = nil
        let request = VisualizeRequest(room: room, placements: placements, items: items, style: style, roomPhoto: roomPhoto)
        let service = self.service
        task = Task {
            do {
                let image = try await service.generate(request)
                guard !Task.isCancelled else { return }
                result = AIImageLabel.stamped(image)
                // Refresh the counts; only successful pictures are counted.
                await auth.loadUsage()
            } catch is CancellationError {
                // Closed while working; nothing to show.
            } catch let error as VisualizeError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = VisualizeError.failed.errorDescription
            }
            isWorking = false
        }
    }

    // MARK: After

    private func resultView(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .accessibilityLabel("AI-generated picture of your room in \(style.title) style")
            Text(AIImageLabel.text)
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: Theme.Space.sm) {
                PrimaryButton(title: "Save", systemImage: "square.and.arrow.down") { save(image) }
                ShareLink(item: Image(uiImage: image), preview: SharePreview("AI-generated inspiration", image: Image(uiImage: image))) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(Typography.headline)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                }
            }
            if let saveMessage {
                Text(saveMessage).font(Typography.caption).foregroundStyle(Theme.textSecondary)
            }
            Button("Try another style") {
                result = nil
                saveMessage = nil
            }
            .font(Typography.subheadline)
            .frame(maxWidth: .infinity, minHeight: Theme.minTap)
        }
    }

    /// Saves to Photos, asking only for "add photos" access.
    private func save(_ image: UIImage) {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                saveMessage = "To save pictures, allow adding photos in Settings."
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                saveMessage = "Saved to Photos."
            } catch {
                saveMessage = "Couldn't save the picture. Please try again."
            }
        }
    }
}
