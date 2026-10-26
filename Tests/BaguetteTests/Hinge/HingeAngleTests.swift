import Testing
@testable import Baguette

/// A foldable's hinge angle, as `HingeControl` reports it from the
/// guest, and which panel that angle leaves lit.
///
/// The simulator runtime decides the swap itself (SpringBoard's pose
/// provider, fed by CoreMotion): closed lights the cover, and from the
/// partially-open region up the unfolded panel takes over. baguette only
/// needs the side of that boundary, because it is what decides which
/// framebuffer to bind and which digitizer to address.
@Suite("HingeAngle")
struct HingeAngleTests {

    // MARK: - parsing HingeControl

    /// The helper prints one line per valid sample.
    @Test func `should read the angle from a HingeControl sample line`() {
        #expect(HingeAngle.parse(hingeControlLine: "angle 130") == HingeAngle(degrees: 130))
        #expect(HingeAngle.parse(hingeControlLine: "angle 3.2") == HingeAngle(degrees: 3.2))
    }

    /// Diagnostics and anything else the helper prints are not samples.
    @Test func `should find no angle when a line is not a sample`() {
        for line in ["", "angle", "angle 130 extra", "angle open", "angle nan", "angle inf", "pid 42", "done 0", "Angle 130"] {
            #expect(HingeAngle.parse(hingeControlLine: line) == nil, "\(line)")
        }
    }
}
