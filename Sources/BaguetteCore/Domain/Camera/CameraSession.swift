import Foundation

/// Owns the camera-streaming state machine for one simulator. Drives
/// three collaborators:
///
///   • `SimulatorInjection`  — arms the dylib env on the target sim
///   • `CameraCapture`       — pulls BGRA frames off a Mac camera
///   • `FrameSink`           — writes those frames into the shared buffer
///
/// `@MainActor` because the WS handler hops here from the NIO event
/// loop and we want a single ordering for state mutations. Frames
/// arrive on the capture queue and re-enter via `Task { @MainActor }`.
@MainActor
final class CameraSession {

    enum Phase: Equatable, Sendable {
        case idle
        case streaming(source: CameraSource)
    }

    private(set) var phase: Phase = .idle
    private(set) var fps: Double = 0
    private(set) var lastError: String?
    private(set) var startedAt: Date?
    private(set) var flags: CameraFlags = CameraFlags()

    private let webcam: any CameraCapture
    private let image: any CameraCapture
    private let video: any CameraCapture
    private let sink: any CameraFrameSink
    private let injection: any SimulatorInjection

    /// The capture serving the current stream — retained so `stop`
    /// tears down exactly the producer that `start` selected.
    private var activeCapture: (any CameraCapture)?

    /// The simulator whose launchd domain we armed with
    /// `DYLD_INSERT_LIBRARIES` — retained so `stop` disarms it. Leaving
    /// it armed loads the dylib into every future app launch on that
    /// sim until it reboots, so teardown must unset it.
    private var armedSimulator: (any Simulator)?

    private var frameCount: UInt64 = 0
    private var fpsLastSample: (Date, UInt64)?

    init(
        webcam: any CameraCapture,
        image: any CameraCapture,
        video: any CameraCapture,
        sink: any CameraFrameSink,
        injection: any SimulatorInjection
    ) {
        self.webcam = webcam
        self.image = image
        self.video = video
        self.sink = sink
        self.injection = injection
    }

    /// The producer that owns `source`. The session is the single place
    /// that maps a source to its capture — no composite abstraction.
    private func capture(for source: CameraSource) -> any CameraCapture {
        switch source {
        case .device: return webcam
        case .image:  return image
        case .video:  return video
        }
    }

    /// Replace the display preferences shipped with each frame. Takes
    /// effect on the next captured frame; no restart.
    func setFlags(_ flags: CameraFlags) {
        self.flags = flags
    }

    /// Arm the dylib on `simulator` and start pulling frames off
    /// `source`. On any failure the session stays `.idle` with
    /// `lastError` populated; callers can read both fields without
    /// catching.
    func start(source: CameraSource, on simulator: any Simulator, dylibPath: String) async {
        guard case .idle = phase else { return }
        do {
            try await injection.arm(dylibPath: dylibPath, on: simulator)
        } catch {
            lastError = error.localizedDescription
            return
        }
        armedSimulator = simulator
        let capture = capture(for: source)
        do {
            try await capture.start(source: source) { [weak self] frame in
                Task { @MainActor in self?.deliver(frame) }
            }
        } catch {
            lastError = error.localizedDescription
            try? await injection.disarm(on: simulator)
            armedSimulator = nil
            return
        }
        activeCapture = capture
        phase = .streaming(source: source)
        startedAt = Date()
        frameCount = 0
        fpsLastSample = nil
        lastError = nil
    }

    /// Tear the stream down and disarm the dylib.
    ///
    /// Every state change is claimed *before* the first `await`. Being
    /// `@MainActor` serialises the steps but doesn't make them atomic:
    /// a second `stop` interleaving at a suspension point would still
    /// read `.streaming`, and go on to stop the same capture and disarm
    /// the same simulator twice.
    func stop() async {
        guard case .streaming = phase else { return }
        let capture = activeCapture
        let sim = armedSimulator
        phase = .idle
        activeCapture = nil
        armedSimulator = nil
        startedAt = nil
        fps = 0
        fpsLastSample = nil

        await capture?.stop()
        if let sim {
            try? await injection.disarm(on: sim)
        }
    }

    /// Tick called by the WS heartbeat (once per second). Computes
    /// instantaneous FPS from the frame-counter delta since the last
    /// sample; first call seeds the baseline and returns fps=0.
    func sampleFPS() {
        let now = Date()
        let count = frameCount
        if let prev = fpsLastSample {
            let dt = now.timeIntervalSince(prev.0)
            let dCount = count >= prev.1 ? count - prev.1 : 0
            fps = dt > 0 ? Double(dCount) / dt : 0
        }
        fpsLastSample = (now, count)
    }

    // MARK: - Frame delivery

    private func deliver(_ frame: CameraFrame) {
        do {
            try sink.write(frame, flags: flags)
            frameCount &+= 1
        } catch {
            lastError = error.localizedDescription
        }
    }
}
