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

    /// One line of `HingeControl read-angle` / `watch-angle` output, a
    /// sample the guest's CoreMotion flagged valid:
    ///
    ///     angle 130
    ///
    /// The first sample carries the current angle and arrives before any
    /// motion, so one line is a reading.
    static func parse(hingeControlLine line: String) -> HingeAngle? {
        let words = line.split(separator: " ", omittingEmptySubsequences: false)
        guard words.count == 2, words[0] == "angle",
              let degrees = Double(words[1]), degrees.isFinite
        else { return nil }
        return HingeAngle(degrees: degrees)
    }
}
