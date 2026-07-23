import Foundation
import IOSurface
import Mockable

/// SimulatorKit's authoritative UI orientation for the selected display.
///
/// These raw values come from `screenProperties.uiOrientation`; they are not
/// inferred from framebuffer dimensions, which are ambiguous during rotation.
enum ScreenOrientation: UInt32, Sendable {
    case portrait = 1
    case portraitUpsideDown = 2
    case landscapeRight = 3
    case landscapeLeft = 4

    init?(simulatorKitRawValue: Int) {
        guard let rawValue = UInt32(exactly: simulatorKitRawValue) else {
            return nil
        }
        self.init(rawValue: rawValue)
    }
}

struct ScreenMetadata: Equatable, Sendable {
    let uiOrientation: ScreenOrientation?
}

/// The simulator's screen — a stream of GPU framebuffer surfaces. Two
/// verbs: `start` to subscribe, `stop` to tear down. Per simulator.
///
/// `IOSurface` is a public Apple type (zero-copy framebuffer), not
/// private API, so it's safe to expose at the domain boundary.
@Mockable
protocol Screen: AnyObject, Sendable {
    /// Subscribe to frame delivery. Throws if SimulatorKit's screen pipe
    /// can't be wired (e.g. simulator isn't booted). Both closures run on
    /// the screen's own dispatch queue; metadata may change without a frame.
    func start(
        onFrame: @escaping @Sendable (IOSurface) -> Void,
        onMetadata: @escaping @Sendable (ScreenMetadata) -> Void
    ) throws

    /// Tear down callbacks and release the underlying screen object.
    func stop()
}

extension Screen {
    /// Existing consumers that only encode pixels can ignore live metadata.
    func start(onFrame: @escaping @Sendable (IOSurface) -> Void) throws {
        try start(onFrame: onFrame, onMetadata: { _ in })
    }
}
