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

    /// `raw` restated in the convention every consumer applies:
    /// landscape-right = 3 turns the plane counter-clockwise, 4 clockwise.
    /// Xcode 27's SimulatorKit reports the two landscapes the other way
    /// round, whatever the guest runs — measured on iPhone 17 under iOS
    /// 26.5 and 27.0 and on both panels of iPhone Duo: the plane reported
    /// as 3 has the interface's top on its left edge. Swapping here keeps
    /// the orientation every host and viewer already speaks meaning one
    /// thing. An unreadable host is left alone.
    static func canonicalRaw(_ raw: Int, xcodeMajor: Int?) -> Int {
        guard let xcodeMajor, xcodeMajor >= 27 else { return raw }
        switch raw {
        case 3:  return 4
        case 4:  return 3
        default: return raw
        }
    }

    /// The major version of a `SimDevice`'s runtime; nil when unreadable.
    static func runtimeMajor(of device: NSObject?) -> Int? {
        guard let runtime = device?.value(forKey: "runtime") as? NSObject,
              runtime.responds(to: NSSelectorFromString("versionString")),
              let version = runtime.value(forKey: "versionString") as? String
        else { return nil }
        return Int(version.prefix { $0 != "." })
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
