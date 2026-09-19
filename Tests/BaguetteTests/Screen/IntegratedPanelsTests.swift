import Testing
@testable import Baguette

/// Which live framebuffer ports are the device's own panels — before
/// Connected Screens has been consulted, from shape alone.
///
/// The count is what decides whether a phone-plane bind is worth a
/// guest round-trip: one panel is the phone; two is a foldable whose
/// panels share the built-in digitizer slot, and only then does the
/// bound panel's screen id matter.
@Suite("IntegratedPanels")
struct IntegratedPanelsTests {

    private func port(_ w: Double, _ h: Double) -> SizedFramebufferPort {
        SizedFramebufferPort(
            portName: "com.apple.framebuffer.display",
            size: Size(width: w, height: h)
        )
    }

    /// iPhone 17 Pro: one portrait port plus the landscape decoys every
    /// device carries (TVOut, CarPlay, the 8K resizable scene).
    @Test func `a phone has one panel among its landscape decoys`() {
        let ports = [port(1206, 2622), port(720, 480), port(7680, 4320), port(720, 480)]
        #expect(IntegratedPanels.count(in: ports) == 1)
        #expect(!IntegratedPanels.several(in: ports))
    }

    /// iPhone Duo: cover and unfolded panels, both portrait.
    @Test func `a foldable has two panels`() {
        let ports = [port(2007, 2853), port(720, 480), port(7680, 4320), port(720, 480), port(1398, 2034)]
        #expect(IntegratedPanels.count(in: ports) == 2)
        #expect(IntegratedPanels.several(in: ports))
    }

    /// An attached 4K external is landscape and never counts as a panel.
    @Test func `an external display is not a panel`() {
        let ports = [port(1206, 2622), port(3840, 2160)]
        #expect(IntegratedPanels.count(in: ports) == 1)
    }

    @Test func `no ports means no panels`() {
        #expect(IntegratedPanels.count(in: []) == 0)
        #expect(!IntegratedPanels.several(in: []))
    }
}
