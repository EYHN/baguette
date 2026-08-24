import Foundation

/// A foldable's hinge angle in degrees — `0` closed, `180` open flat —
/// as the host reads it back from the device.
///
/// The angle is the simulator runtime's: Device Hub streams hinge
/// samples into the guest as HID reports, CoreMotion delivers them to
/// SpringBoard, and SpringBoard's pose provider decides which panel to
/// light. baguette does not decide the pose; it reads the angle and
/// follows it, because the framebuffer it binds and the digitizer it
/// addresses both depend on the lit panel.
struct HingeAngle: Equatable, Sendable {
    let degrees: Double

    /// Where SpringBoard hands the display over to the unfolded panel.
    ///
    /// Measured on iPhone Duo / iOS 27.1 with the runtime's own
    /// transition rules: sweeping to 60° left the cover lit, sweeping to
    /// 90° lit the unfolded panel, and the pose provider's regions
    /// (`closed` / `partiallyOpen` / `openFlat`) begin the partially-open
    /// band there. Device Hub's poses land well clear of it on either
    /// side (closed ≈ 3°, open ≈ 130–180°).
    static let openBoundaryDegrees: Double = 90

    var litPanel: IntegratedPanel {
        degrees >= Self.openBoundaryDegrees ? .secondary : .primary
    }

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
