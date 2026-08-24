import Foundation
import Mockable

/// What moves a foldable's hinge — and turns the device — the way Device
/// Hub's pose picker and rotate button do. The production impl is
/// `GuestHingeMotor`, which runs `HingeControl` inside the guest.
@Mockable
protocol HingeMotor: Sendable {
    /// Sweep the hinge from one angle to another over `duration` seconds,
    /// at 60 Hz with an ease-out, as Device Hub's picker plays a pose
    /// change. Returns when the sweep has been delivered.
    func fold(from: Double, to: Double, over duration: TimeInterval) throws

    /// Turn the device to an interface orientation through the same
    /// channel Device Hub's rotate button uses.
    func turn(to orientation: DeviceOrientation) throws
}

enum HingeError: Error, Equatable {
    /// The build did not ship `HingeControl`, or it could not be installed.
    case toolMissing
    case toolFailed(status: Int32)
}
