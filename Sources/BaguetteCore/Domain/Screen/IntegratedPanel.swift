import Foundation

/// One of a device's own display panels, by CoreSimulator's name for it.
///
/// Every device has a `primary`. A foldable (iPhone Duo) adds a
/// `primary-1` — the unfolded panel — and which of the two is lit is
/// Core Device's word, not the name's: see `Simulator.litPanel()`.
enum IntegratedPanel: Equatable, Sendable {
    case primary
    case secondary

    /// From the `Device Name:` a Connected Screens record carries, or
    /// `capabilities.plist`'s `deviceName`. Externals (`external-0`,
    /// `wireless0`, `resizable`) and older output without a name are
    /// not panels.
    static func named(_ deviceName: String) -> IntegratedPanel? {
        switch deviceName {
        case "primary": return .primary
        case "primary-1": return .secondary
        default: return nil
        }
    }
}
