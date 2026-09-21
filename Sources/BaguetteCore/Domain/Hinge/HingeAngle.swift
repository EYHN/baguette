import Foundation

/// A foldable's hinge angle in degrees — `0` closed, `180` open flat —
/// as the host reads it back from the device.
///
/// The angle is the simulator runtime's: Device Hub streams hinge
/// samples into the guest as HID reports, CoreMotion delivers them to
/// SpringBoard, and SpringBoard's pose provider decides which panel to
/// light. baguette does not decide the pose; it reads the angle to
/// draw the fold at the angle the device is actually at.
///
/// The angle says nothing about which panel is lit. The pose provider
/// decides from angle, speed and history — the same 30° has been seen
/// with the cover lit and with the unfolded panel lit, depending on
/// which way the hinge was moving — and an app may light the cover
/// while the device is open. Core Device is the one authority on that
/// (`Simulator.litPanel()`, through `ActiveDisplays`).
struct HingeAngle: Equatable, Sendable {
    let degrees: Double

    /// One line of `xcrun devicectl device motion hinge-angle` output:
    ///
    ///     • +0.000s : Angle:130.0°  Mech:130.0°  Velocity:+0.0°/s  AngleValid:Y  VelocityValid:N  Range:0-180°
    ///
    /// The first sample carries the current angle and arrives before any
    /// motion, so one line is a reading. A sample the device flags
    /// `AngleValid:N` is not.
    static func parse(devicectlLine line: String) -> HingeAngle? {
        guard line.contains("AngleValid:Y") else { return nil }
        let pattern = #/Angle:\s*(-?[0-9]+(?:\.[0-9]+)?)°/#
        guard let match = line.firstMatch(of: pattern),
              let degrees = Double(match.1)
        else { return nil }
        return HingeAngle(degrees: degrees)
    }
}
