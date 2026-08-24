import Testing
import Foundation
@testable import BaguetteCore

/// The sentences `baguette record` prints on its way out. They are
/// asserted because a recording fails minutes after the user walked
/// away — the message is the whole diagnosis, and a wrong one sends
/// them looking in the wrong place.
@Suite("RecordingError")
struct RecordingErrorTests {

    @Test func `an unwritable container names the ones baguette can write`() {
        #expect(RecordingError.unsupportedContainer("webm").message
            == "Unknown recording container 'webm'. Expected one of: mp4 | mov")
    }

    @Test func `a device that isn't booted is named as the reason, not blamed on a still screen`() {
        // A shut-down simulator has no framebuffer to wire, so it
        // delivers nothing — and "the screen never changed. Drive some
        // input" would send the user tapping at a device that isn't
        // running. Say what's actually wrong and what fixes it.
        let error = RecordingError.deviceNotBooted("Shutdown")

        #expect(error.message
            == "Cannot record a Shutdown device — boot it first "
                + "with `baguette boot --udid <UDID>`.")
    }

    @Test func `a writer failure carries the reason it failed`() {
        #expect(RecordingError.writerFailed("disk full").message
            == "Recording failed: disk full")
    }

    @Test func `the no-frames failure explains that no frame ever arrived`() {
        #expect(RecordingError.noFramesCaptured.message
            == "No frames captured — the simulator screen never changed. "
                + "Drive some input while recording.")
    }
}
