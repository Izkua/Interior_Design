import SwiftUI
import RealityKit
import os

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
private let scanLog = Logger(subsystem: "com.isabellasi.InteriorDesign", category: "ObjectScan")

struct ObjectScanView: View {
    /// Called with the finished model (USDZ file contents).
    let onFinished: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var session: ObjectCaptureSession?
    @State private var phase: Phase = .starting
    /// True once we've waited a long time for the camera to get going.
    @State private var isSlowToStart = false
    @State private var startWatcher: Task<Void, Never>?
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
        // Also follow the session's state directly (it's observable), in
        // case an update from `stateUpdates` is missed.
        .onChange(of: stateName) { _, name in
            scanLog.info("state (observed): \(name, privacy: .public)")
            if let session, case .ready = session.state { tryStartDetecting(session) }
        }
        .onDisappear {
            startWatcher?.cancel()
            cleanUp()
        }
    }

    private var isScanning: Bool {
        phase == .detecting || phase == .capturing || phase == .starting
    }

    @ViewBuilder
    private var panel: some View {
        VStack(spacing: Theme.Space.sm) {
            switch phase {
            case .starting:
                if isSlowToStart {
                    Text("Still waiting for the camera. Close any other camera apps, then try again in good light.")
                        .multilineTextAlignment(.center)
                    PrimaryButton(title: "Close", systemImage: "xmark") { cancel() }
                } else {
                    ProgressView().tint(.white)
                    Text("Getting the camera ready…")
                    Text("Move your iPhone slowly and point it at the floor near the piece.")
                        .font(Typography.caption)
                        .multilineTextAlignment(.center)
                }
                // Shows what the camera is doing, so it's clear it isn't stuck.
                Text("Camera status: \(stateName)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
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

    /// The session's state as text, for logging and change tracking.
    private var stateName: String {
        session.map { String(describing: $0.state) } ?? "none"
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
        scanLog.info("session started, state: \(String(describing: newSession.state), privacy: .public)")
        startWatcher = Task { await watchStart(newSession) }

        // The session can already be ready before we start listening, and
        // the updates below only report changes, so look at where it is
        // now first. (Missing that left the screen stuck on "Getting the
        // camera ready".)
        if await handle(newSession.state, session: newSession, images: images, checkpoint: checkpoint) { return }
        for await state in newSession.stateUpdates {
            scanLog.info("state: \(String(describing: state), privacy: .public)")
            if await handle(state, session: newSession, images: images, checkpoint: checkpoint) { return }
        }
    }

    /// Reacts to one session state. Returns true when scanning is over.
    private func handle(_ state: ObjectCaptureSession.CaptureState, session newSession: ObjectCaptureSession,
                        images: URL, checkpoint: URL) async -> Bool {
        switch state {
        case .ready:
            // Starting to look for the piece moves on to .detecting. This
            // can be refused until the camera is tracking, and then no new
            // state arrives, so `watchStart` keeps trying.
            tryStartDetecting(newSession)
        case .detecting:
            phase = .detecting
        case .capturing:
            phase = .capturing
        case .completed:
            await build(images: images, checkpoint: checkpoint)
            return true
        case .failed(let error):
            scanLog.error("session failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed("The scan stopped: \(error.localizedDescription)")
            return true
        default:
            break
        }
        return false
    }

    /// Asks the session to start looking for the piece, once it's ready.
    private func tryStartDetecting(_ session: ObjectCaptureSession) {
        guard phase == .starting, case .ready = session.state else { return }
        if session.startDetecting() {
            scanLog.info("startDetecting accepted")
            phase = .detecting
        } else {
            scanLog.info("startDetecting refused, will retry")
        }
    }

    /// While the camera is getting ready, retries starting detection every
    /// second, and after 15 seconds shows a hint with a Close button.
    private func watchStart(_ session: ObjectCaptureSession) async {
        let began = Date.now
        while !Task.isCancelled, phase == .starting {
            tryStartDetecting(session)
            if !isSlowToStart, Date.now.timeIntervalSince(began) > 15, phase == .starting {
                scanLog.error("still starting after 15 s, state: \(String(describing: session.state), privacy: .public)")
                isSlowToStart = true
            }
            try? await Task.sleep(for: .seconds(1))
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
        startWatcher?.cancel()
        session?.cancel()
        dismiss()
    }

    /// Scan photos are large; they're thrown away once the model is made.
    private func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }
}
#endif
