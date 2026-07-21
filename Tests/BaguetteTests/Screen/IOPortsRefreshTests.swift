import Testing
@testable import BaguetteCore

/// Creating ports is only necessary when the device exposes none.
/// Calling updateIOPorts against an already-connected TVOut/CarPlay
/// resets guest display services and wedges the external surface.
@Suite("IOPortsRefresh")
struct IOPortsRefreshTests {
    @Test func doesNotRefreshWhenFramebufferDisplayPortsAlreadyExist() {
        #expect(IOPortsRefresh.shouldUpdate(hasFramebufferDisplayPorts: true) == false)
    }

    @Test func refreshesOnlyWhenNoFramebufferDisplayPortsExist() {
        #expect(IOPortsRefresh.shouldUpdate(hasFramebufferDisplayPorts: false) == true)
    }
}
