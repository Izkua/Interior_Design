import SwiftUI
import RealityKit

/// Scans a piece of furniture into a real 3D model with Apple's Object
/// Capture: walk slowly around it while the phone takes photos, then the
/// phone builds a textured model (USDZ) at true size. Free, on the phone.
///
/// Object Capture needs a LiDAR sensor (Pro iPhones), so this is only
/// offered when `ObjectScan.isSupported`. Other phones use the AR preview
/// and can import a model made elsewhere.
enum ObjectScan {
    /// True on phones that can scan objects (those with LiDAR). Asks the
    /// system rather than guessing from the phone's name.
    @MainActor static var isSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported
        #endif
    }
}

#if !targetEnvironment(simulator)
struct ObjectScanView: View {
    /// Called with the finished model (USDZ file contents).
    let onFinished: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var session: ObjectCaptureSession?
    @State private var phase: Phase = .starting
    @State private var folder = FileManager.default.temporaryDirectory.appendingPathComponent("ObjectScan-\(UUID().uuidString)", isDirectory: true)

    enum Phase: Equatable {
        case starting
        case detecting
        case capturing
        case building(Double)
        case failed(String)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let session, isScanning {
                ObjectCaptureView(session: session)
                    .ignoresSafeArea()
            }
            VStack(spacing: Theme.Space.md) {
                HStack {
                    Button("Cancel") { cancel() }
                        .font(Typography.headline)
                        .frame(minHeight: Theme.minTap)
                        .padding(.horizontal, 14)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
                Spacer()
                panel
            }
            .padding(Theme.Space.md)
            .foregroundStyle(.white)
        }
        .statusBarHidden()
        .task { await start() }
        .onDisappear { cleanUp() }
    }

    private var isScanning: Bool {
        phase == .detecting || phase == .capturing || phase == .starting
    }

    @ViewBuilder
    private var panel: some View {
        VStack(spacing: Theme.Space.sm) {
            switch phase {
            case .starting:
                ProgressView().tint(.white)
                Text("Getting the camera ready…")
            case .detecting:
                Text("Point at the piece so the box fits around it. Drag the box's edges to adjust.")
                    .multilineTextAlignment(.center)
                PrimaryButton(title: "Start scanning", systemImage: "viewfinder") {
                    session?.startCapturing()
                }
            case .capturing:
                Text(captureHint)
                    .multilineTextAlignment(.center)
                PrimaryButton(title: "Finish and build 3D model", systemImage: "cube") {
                    session?.finish()
                }
                .disabled(!canFinish)
                .opacity(canFinish ? 1 : 0.6)
            case .building(let fraction):
                Text("Building the 3D model…")
                    .font(Typography.headline)
                ProgressView(value: fraction)
                    .tint(Theme.accent)
                Text("This takes a few minutes. Keep the app open.")
                    .font(Typography.caption)
            case .failed(let message):
                Text(message)
                    .multilineTextAlignment(.center)
                PrimaryButton(title: "Close", systemImage: "xmark") { cancel() }
            }
        }
        .font(Typography.subheadline)
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var shots: Int { session?.numberOfShotsTaken ?? 0 }
    private var canFinish: Bool { (session?.userCompletedScanPass ?? false) || shots >= 30 }

    private var captureHint: String {
        if session?.userCompletedScanPass == true {
            return "Nice, that's a full circle. Finish now, or go around again lower down for more detail."
        }
        return "Walk slowly all the way around the piece, keeping it in view. \(shots) photos so far."
    }

    // MARK: Steps

    private func start() async {
        guard session == nil else { return }
        let images = folder.appendingPathComponent("Images", isDirectory: true)
        let checkpoint = folder.appendingPathComponent("Checkpoint", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
        } catch {
            phase = .failed("Couldn't make room for the scan on this phone.")
            return
        }
        var configuration = ObjectCaptureSession.Configuration()
        configuration.checkpointDirectory = checkpoint
        let newSession = ObjectCaptureSession()
        newSession.start(imagesDirectory: images, configuration: configuration)
        session = newSession

        for await state in newSession.stateUpdates {
            switch state {
            case .ready:
                if newSession.startDetecting() { phase = .detecting }
            case .detecting:
                phase = .detecting
            case .capturing:
                phase = .capturing
            case .completed:
                await build(images: images, checkpoint: checkpoint)
                return
            case .failed(let error):
                phase = .failed("The scan stopped: \(error.localizedDescription)")
                return
            default:
                break
            }
        }
    }

    /// Turns the photos into a 3D model, on the phone.
    private func build(images: URL, checkpoint: URL) async {
        phase = .building(0)
        session = nil
        let output = folder.appendingPathComponent("model.usdz")
        do {
            var configuration = PhotogrammetrySession.Configuration()
            configuration.checkpointDirectory = checkpoint
            let photogrammetry = try PhotogrammetrySession(input: images, configuration: configuration)
            try photogrammetry.process(requests: [.modelFile(url: output)])
            for try await event in photogrammetry.outputs {
                switch event {
                case .requestProgress(_, let fraction):
                    phase = .building(fraction)
                case .requestError(_, let error):
                    phase = .failed("Couldn't build the model: \(error.localizedDescription)")
                    return
                case .processingCancelled:
                    phase = .failed("Building the model was stopped.")
                    return
                case .processingComplete:
                    guard let data = try? Data(contentsOf: output) else {
                        phase = .failed("The model couldn't be saved.")
                        return
                    }
                    onFinished(data)
                    dismiss()
                    return
                default:
                    break
                }
            }
        } catch {
            phase = .failed("Couldn't build the model: \(error.localizedDescription)")
        }
    }

    private func cancel() {
        session?.cancel()
        dismiss()
    }

    /// Scan photos are large; they're thrown away once the model is made.
    private func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }
}
#endif
