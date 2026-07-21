import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// Behaviour spec for the CameraSession state machine. The session
/// owns three collaborators (capture, sink, injection). Tests inject
/// the auto-generated `MockXxx` and assert on returned state.
@Suite("CameraSession")
@MainActor
struct CameraSessionTests {

    private static let webcam = CameraSource.device(uid: "u-1")

    /// Captures `start(source:onFrame:)` callbacks so the test can
    /// fire frames through the orchestrator on demand.
    final class Captures: @unchecked Sendable {
        var onFrame: (@Sendable (CameraFrame) -> Void)?
    }

    private struct Wiring {
        let session: CameraSession
        let webcam: MockCameraCapture
        let image: MockCameraCapture
        let video: MockCameraCapture
        let sink: MockCameraFrameSink
        let injection: MockSimulatorInjection
        let sim: MockSimulator
        let captures: Captures
    }

    /// Bare wiring — mocks are created but NOT pre-stubbed. Each test
    /// configures only the behaviours it needs so overrides don't
    /// collide with FIFO matching.
    private func makeWiring() -> Wiring {
        let webcam = MockCameraCapture()
        let image = MockCameraCapture()
        let video = MockCameraCapture()
        let sink = MockCameraFrameSink()
        let injection = MockSimulatorInjection()
        let sim = MockSimulator()
        given(sim).udid.willReturn("sim-U")
        let captures = Captures()
        let session = CameraSession(
            webcam: webcam, image: image, video: video,
            sink: sink, injection: injection
        )
        return Wiring(
            session: session, webcam: webcam, image: image, video: video,
            sink: sink, injection: injection, sim: sim, captures: captures
        )
    }

    /// Helper for happy-path stubs — call from each test that wants
    /// the webcam capture to succeed and record the onFrame callback.
    private func stubHappyCapture(_ w: Wiring) {
        given(w.webcam).start(source: .any, onFrame: .any).willProduce { _, onFrame in
            w.captures.onFrame = onFrame
        }
    }

    @Test func `starts in idle phase with no error and zero fps`() {
        let w = makeWiring()
        #expect(w.session.phase == .idle)
        #expect(w.session.fps == 0)
        #expect(w.session.lastError == nil)
    }

    @Test func `start arms the dylib and kicks off capture`() async {
        let w = makeWiring()
        given(w.injection).arm(dylibPath: .any, on: .any).willReturn(())
        stubHappyCapture(w)

        await w.session.start(source: Self.webcam, on: w.sim, dylibPath: "/tmp/vc.dylib")

        verify(w.injection).arm(dylibPath: .value("/tmp/vc.dylib"), on: .any).called(1)
        verify(w.webcam).start(source: .value(Self.webcam), onFrame: .any).called(1)
        #expect(w.session.phase == .streaming(source: Self.webcam))
        #expect(w.session.lastError == nil)
    }

    @Test func `an image source is routed to the image capture, not the webcam or video`() async {
        let w = makeWiring()
        given(w.injection).arm(dylibPath: .any, on: .any).willReturn(())
        given(w.image).start(source: .any, onFrame: .any).willReturn(())

        let source = CameraSource.image(path: "/tmp/pic.png")
        await w.session.start(source: source, on: w.sim, dylibPath: "/tmp/vc.dylib")

        verify(w.image).start(source: .value(source), onFrame: .any).called(1)
        verify(w.webcam).start(source: .any, onFrame: .any).called(0)
        verify(w.video).start(source: .any, onFrame: .any).called(0)
        #expect(w.session.phase == .streaming(source: source))
    }

    @Test func `stop tears down the capture that was started for the active source`() async {
        let w = makeWiring()
        given(w.injection).arm(dylibPath: .any, on: .any).willReturn(())
        given(w.injection).disarm(on: .any).willReturn(())
        given(w.video).start(source: .any, onFrame: .any).willReturn(())
        given(w.video).stop().willReturn(())

        await w.session.start(source: .video(path: "/tmp/clip.mp4"), on: w.sim, dylibPath: "/tmp/vc.dylib")
        await w.session.stop()

        verify(w.video).stop().called(1)
        verify(w.webcam).stop().called(0)
        #expect(w.session.phase == .idle)
    }

    @Test func `start failure on injection leaves the session idle with an error`() async {
        let w = makeWiring()
        given(w.injection).arm(dylibPath: .any, on: .any)
            .willThrow(NSError(
                domain: "test", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "no perm"]
            ))

        await w.session.start(source: Self.webcam, on: w.sim, dylibPath: "/tmp/vc.dylib")

        verify(w.webcam).start(source: .any, onFrame: .any).called(0)
        #expect(w.session.phase == .idle)
        #expect(w.session.lastError?.contains("no perm") == true)
    }

    @Test func `start failure on capture leaves the session idle with an error`() async {
        let w = makeWiring()
        given(w.injection).arm(dylibPath: .any, on: .any).willReturn(())
        given(w.injection).disarm(on: .any).willReturn(())
        // Override `start` to throw instead of capturing the closure.
        given(w.webcam).start(source: .any, onFrame: .any)
            .willThrow(NSError(
                domain: "test", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "device busy"]
            ))

        await w.session.start(source: Self.webcam, on: w.sim, dylibPath: "/tmp/vc.dylib")

        #expect(w.session.phase == .idle)
        #expect(w.session.lastError?.contains("device busy") == true)
    }

    @Test func `incoming frames are written to the sink with the current flags`() async throws {
        let w = makeWiring()
        given(w.injection).arm(dylibPath: .any, on: .any).willReturn(())
        given(w.sink).write(.any, flags: .any).willReturn(())
        stubHappyCapture(w)

        w.session.setFlags(CameraFlags(fillGravity: true, mirror: false))
        await w.session.start(source: Self.webcam, on: w.sim, dylibPath: "/tmp/vc.dylib")

        let frame = try CameraFrame(
            sequence: 1, timestampMs: 100, width: 2, height: 2, pixels: Data(count: 16)
        )
        w.captures.onFrame?(frame)
        await Task.yield()

        verify(w.sink).write(.any, flags: .value(CameraFlags(fillGravity: true, mirror: false)))
            .called(1)
    }

    @Test func `stop drops back to idle and tears down capture`() async {
        let w = makeWiring()
        given(w.injection).arm(dylibPath: .any, on: .any).willReturn(())
        given(w.injection).disarm(on: .any).willReturn(())
        given(w.webcam).stop().willReturn(())
        stubHappyCapture(w)

        await w.session.start(source: Self.webcam, on: w.sim, dylibPath: "/tmp/vc.dylib")
        await w.session.stop()

        verify(w.webcam).stop().called(1)
        #expect(w.session.phase == .idle)
        #expect(w.session.fps == 0)
    }

    @Test func `stop disarms the dylib on the simulator it armed`() async {
        let w = makeWiring()
        given(w.injection).arm(dylibPath: .any, on: .any).willReturn(())
        given(w.injection).disarm(on: .any).willReturn(())
        given(w.webcam).stop().willReturn(())
        stubHappyCapture(w)

        await w.session.start(source: Self.webcam, on: w.sim, dylibPath: "/tmp/vc.dylib")
        await w.session.stop()

        // Injection must be removed on teardown — leaving DYLD_INSERT_LIBRARIES
        // armed loads the dylib into every future app launch until reboot.
        verify(w.injection).disarm(on: .any).called(1)
    }

    /// `stop` suspends twice (tearing down capture, then disarming the
    /// dylib). Being `@MainActor` serialises those steps but doesn't stop
    /// a second `stop` from interleaving at a suspension point — and if
    /// the phase is still `.streaming` when it looks, it tears the same
    /// session down a second time.
    @Test func `a stop that lands mid-teardown doesn't tear down twice`() async {
        let w = makeWiring()
        given(w.injection).arm(dylibPath: .any, on: .any).willReturn(())
        given(w.injection).disarm(on: .any).willReturn(())
        given(w.webcam).stop().willReturn(())
        stubHappyCapture(w)

        await w.session.start(source: Self.webcam, on: w.sim, dylibPath: "/tmp/vc.dylib")
        async let first: Void = w.session.stop()
        async let second: Void = w.session.stop()
        _ = await (first, second)

        verify(w.webcam).stop().called(1)
        verify(w.injection).disarm(on: .any).called(1)
        #expect(w.session.phase == .idle)
    }

    @Test func `sampleFPS divides frame delta by elapsed seconds`() async throws {
        let w = makeWiring()
        given(w.injection).arm(dylibPath: .any, on: .any).willReturn(())
        given(w.sink).write(.any, flags: .any).willReturn(())
        stubHappyCapture(w)

        await w.session.start(source: Self.webcam, on: w.sim, dylibPath: "/tmp/vc.dylib")
        w.session.sampleFPS()  // seed baseline; fps stays 0

        let frame = try CameraFrame(
            sequence: 1, timestampMs: 0, width: 2, height: 2, pixels: Data(count: 16)
        )
        for _ in 0..<30 { w.captures.onFrame?(frame) }
        await Task.yield()

        // Wait at least 100 ms so the divisor is well-defined.
        try await Task.sleep(nanoseconds: 110_000_000)
        w.session.sampleFPS()

        #expect(w.session.fps > 0)
    }
}
