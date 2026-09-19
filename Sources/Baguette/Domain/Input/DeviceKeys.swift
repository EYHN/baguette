import Foundation
import Mockable

/// A device's hardware keys, pressed the way Device Hub presses them:
/// one HID key event down, held, then up, on the guest daemon's own
/// buttons service. iPhone Duo's SpringBoard takes volume, power and
/// the camera control only from there — the legacy Indigo press lands
/// on a touchscreen service and is ignored. The production impl is
/// `GuestHingeMotor`, which runs `HingeControl` inside the guest.
@Mockable
protocol DeviceKeys: Sendable {
    /// Press `usage` for `hold` seconds. Throws when the guest tool is
    /// missing or refused.
    func press(_ usage: HIDUsage, hold: TimeInterval) throws
}
