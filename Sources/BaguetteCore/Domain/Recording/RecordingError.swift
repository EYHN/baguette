import Foundation

/// Everything `baguette record` can refuse to do, with the sentence the
/// CLI prints on the way out. Kept `Equatable` so the suites assert on
/// the failure itself rather than on a string match.
enum RecordingError: Error, Equatable {
    /// The `--output` filename doesn't name a container baguette writes.
    case unsupportedContainer(String)
    /// The device isn't running, so it has no framebuffer to record.
    /// Caught up front: without this the recording would sit out its
    /// whole `--duration` and then report `noFramesCaptured`, which
    /// blames a still screen for a device that was never on.
    case deviceNotBooted(String)
    /// The recording ended without a single frame. SimulatorKit only
    /// fires its framebuffer callback on a frame *change*, so a
    /// quiescent simulator delivers nothing at all — that is far more
    /// often the cause than a broken pipeline, and the message says so.
    case noFramesCaptured
    /// `AVAssetWriter` rejected the session or failed mid-write.
    case writerFailed(String)

    var message: String {
        switch self {
        case .unsupportedContainer(let container):
            return "Unknown recording container '\(container)'. "
                + "Expected one of: \(RecordingFormat.containerList)"
        case .deviceNotBooted(let state):
            return "Cannot record a \(state) device — boot it first "
                + "with `baguette boot --udid <UDID>`."
        case .noFramesCaptured:
            return "No frames captured — the simulator screen never changed. "
                + "Drive some input while recording."
        case .writerFailed(let reason):
            return "Recording failed: \(reason)"
        }
    }
}
