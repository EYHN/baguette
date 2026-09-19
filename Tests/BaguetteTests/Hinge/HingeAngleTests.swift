import Testing
@testable import Baguette

/// A foldable's hinge angle, as `devicectl device motion hinge-angle`
/// reports it, and which panel that angle leaves lit.
///
/// The simulator runtime decides the swap itself (SpringBoard's pose
/// provider, fed by CoreMotion): closed lights the cover, and from the
/// partially-open region up the unfolded panel takes over. baguette only
/// needs the side of that boundary, because it is what decides which
/// framebuffer to bind and which digitizer to address.
@Suite("HingeAngle")
struct HingeAngleTests {

    // MARK: - parsing devicectl

    /// The monitor prints one line per sample; the first one is the
    /// current angle and arrives before any motion.
    @Test func `parses the angle from a devicectl sample line`() {
        let line = "• +0.000s : Angle:130.0°  Mech:130.0°  Velocity:+0.0°/s  AngleValid:Y  VelocityValid:N  Range:0-180°"
        #expect(HingeAngle.parse(devicectlLine: line) == HingeAngle(degrees: 130))
    }

    @Test func `parses a padded small angle`() {
        let line = "• +0.000s : Angle:  3.2°  Mech:  3.2°  Velocity:+0.0°/s  AngleValid:Y  VelocityValid:N  Range:0-180°"
        #expect(HingeAngle.parse(devicectlLine: line) == HingeAngle(degrees: 3.2))
    }

    /// The banner and anything else the tool prints is not a sample.
    @Test func `ignores lines that are not samples`() {
        #expect(HingeAngle.parse(devicectlLine: "Hinge angle monitoring started. 60 seconds remaining:") == nil)
        #expect(HingeAngle.parse(devicectlLine: "") == nil)
        #expect(HingeAngle.parse(devicectlLine: "Angle:") == nil)
    }

    /// A sample whose angle the device itself flags invalid is no reading.
    @Test func `an invalid sample is not an angle`() {
        let line = "• +0.000s : Angle:  0.0°  Mech:  0.0°  Velocity:+0.0°/s  AngleValid:N  VelocityValid:N  Range:0-180°"
        #expect(HingeAngle.parse(devicectlLine: line) == nil)
    }

    // MARK: - lit panel

    @Test func `closed lights the cover`() {
        #expect(HingeAngle(degrees: 0).litPanel == .primary)
        #expect(HingeAngle(degrees: 3.2).litPanel == .primary)
        #expect(HingeAngle(degrees: 60).litPanel == .primary)
    }

    @Test func `open lights the unfolded panel`() {
        #expect(HingeAngle(degrees: 180).litPanel == .secondary)
        #expect(HingeAngle(degrees: 130).litPanel == .secondary)
        #expect(HingeAngle(degrees: 90).litPanel == .secondary)
    }

    @Test func `the swap boundary is where SpringBoard's partially-open region begins`() {
        #expect(HingeAngle(degrees: HingeAngle.openBoundaryDegrees).litPanel == .secondary)
        #expect(HingeAngle(degrees: HingeAngle.openBoundaryDegrees - 1).litPanel == .primary)
    }
}
