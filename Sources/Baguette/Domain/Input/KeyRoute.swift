import Foundation

/// How a key press reaches the guest.
///
/// Keys were pushed through the touch target as arbitrary page-7 usages.
/// On an iOS 27 runtime backboardd finds no destination for keys arriving
/// from the touchscreen sender and drops them; the legacy keyboard
/// service's own message (`IndigoHIDMessageForKeyboardArbitrary`) reaches
/// the focused app. That is the one combination this was measured on, so
/// it is the one combination that changes — older runtimes keep the path
/// they were verified with.
enum KeyRoute: Equatable, Sendable {
    case keyboardService
    case touchTarget

    static func choose(runtimeMajor: Int?) -> KeyRoute {
        guard let runtimeMajor, runtimeMajor >= 27 else { return .touchTarget }
        return .keyboardService
    }
}
