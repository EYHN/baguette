import Foundation

/// Resolves the Indigo HID digitizer target for a display plane.
/// Phone always uses the integrated constant; CarPlay derives from
/// the live connected screen id via `IndigoHIDTargetForScreen`.
enum DisplayTouchTarget {
    static func resolve(
        kind: DisplayKind,
        connectedScreenId: UInt32,
        derive: (UInt32) -> UInt32?
    ) -> UInt32 {
        switch kind {
        case .phone:
            return IndigoHIDTouchTarget.phone
        case .carPlay:
            return derive(connectedScreenId) ?? IndigoHIDTouchTarget.phone
        }
    }
}
