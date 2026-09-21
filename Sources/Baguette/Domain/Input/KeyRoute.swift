import Foundation

/// How a key press reaches the guest.
///
/// Keys were historically pushed through the touch target as arbitrary
/// page-7 usages. On an iOS 27 runtime, backboardd finds no destination
/// for keys arriving from the touchscreen sender and drops them; the
/// legacy keyboard service's own message
/// (`IndigoHIDMessageForKeyboardArbitrary`) reaches the focused app.
/// That is the one combination this was measured on (iPhone 17e / iPhone
/// Duo under iOS 27: 0/4 through the touch target, 4/4 through the
/// keyboard service; a fresh iPhone 17 accepts either), so it is the
/// one combination that changes — older runtimes keep the path they
/// were verified with.
enum KeyRoute: Equatable, Sendable {
    case keyboardService
    case touchTarget

    static func choose(runtimeMajor: Int?) -> KeyRoute {
        guard let runtimeMajor, runtimeMajor >= 27 else { return .touchTarget }
        return .keyboardService
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
