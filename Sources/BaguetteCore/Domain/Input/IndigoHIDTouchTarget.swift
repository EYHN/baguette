import Foundation

/// Indigo HID digitizer routing targets. Phone uses the integrated
/// touch constant; external planes (CarPlay) supply a target derived
/// from `IndigoHIDTargetForScreen(connectedScreenId)` outside Domain.
enum IndigoHIDTouchTarget {
    /// Integrated phone digitizer (`0x32`).
    static let phone: UInt32 = 0x32
}
