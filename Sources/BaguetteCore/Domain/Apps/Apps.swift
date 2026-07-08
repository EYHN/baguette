import Foundation
import Mockable

/// The apps installed on a device — "the apps on my phone." You add to
/// the collection by installing an `AppBundle`; uninstall / list aren't
/// modelled yet (drag-and-drop only ever *adds*). Named as the plural
/// collection noun per the aggregate convention, alongside `Simulators`
/// / `Chromes` / `Cameras`.
///
/// `@Mockable` so the serve route and CLI command can be unit-tested
/// without a booted simulator. The production impl is `SimctlApps`,
/// backed by `xcrun simctl install`.
@Mockable
protocol Apps: Sendable {
    /// Install an app onto the device. Throws `AppsError.installFailed`
    /// when simctl exits non-zero (device not booted, bad bundle, …).
    func install(_ app: AppBundle) async throws
}

/// Failure modes surfaced when installing an app. Maps to a CLI exit
/// message and an HTTP 5xx on the serve route.
enum AppsError: Error, Equatable, CustomStringConvertible {
    case installFailed(status: Int32)

    var description: String {
        switch self {
        case .installFailed(let status):
            return "xcrun simctl install exited \(status)"
        }
    }
}
