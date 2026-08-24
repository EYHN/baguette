import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// Host External Displays enablement: probe Connected Screens first;
/// only click the I/O panel when CarPlay is absent; a second call is
/// a no-op against the connected end state.
@Suite("HostExternalDisplays")
struct HostExternalDisplaysTests {

    private let connectedEnumerate = """
        Connected Screens:
        (1) LCD:
            Screen ID: 1
            Screen Type: Integrated
            Pixel Size: {1206, 2622}
        (2) TVOut:
            Screen ID: 2
            Screen Type: TVOut
            Pixel Size: {720, 480}
        """

    private let phoneOnlyEnumerate = """
        Connected Screens:
        (1) LCD:
            Screen ID: 1
            Screen Type: Integrated
            Pixel Size: {1206, 2622}
        """

    @Test func `enableCarPlay is a no-op when Connected Screens already list TVOut`() throws {
        let panel = MockExternalDisplayPanel()
        given(panel).enableCarPlay().willReturn()
        let external = HostExternalDisplays(
            panel: panel,
            enumerateIO: { self.connectedEnumerate }
        )

        #expect(external.isCarPlayConnected)
        try external.enableCarPlay()
        verify(panel).enableCarPlay().called(0)
        #expect(external.isCarPlayConnected)
    }

    @Test func `enableCarPlay clicks the panel then reports connected`() throws {
        let panel = MockExternalDisplayPanel()
        given(panel).enableCarPlay().willReturn()
        let state = EnumerateState(text: phoneOnlyEnumerate)
        let external = HostExternalDisplays(
            panel: panel,
            enumerateIO: { state.text }
        )

        #expect(!external.isCarPlayConnected)
        try external.enableCarPlay()
        state.text = connectedEnumerate
        #expect(external.isCarPlayConnected)
        verify(panel).enableCarPlay().called(1)

        try external.enableCarPlay()
        verify(panel).enableCarPlay().called(1)
    }

    @Test func `enableCarPlay tracks enabled after panel success when probe stays empty`() throws {
        let panel = MockExternalDisplayPanel()
        given(panel).enableCarPlay().willReturn()
        let external = HostExternalDisplays(
            panel: panel,
            enumerateIO: { self.phoneOnlyEnumerate }
        )

        try external.enableCarPlay()
        #expect(external.isCarPlayConnected)
        try external.enableCarPlay()
        verify(panel).enableCarPlay().called(1)
    }

    /// Enabling is guarded by the probe, and rightly so — clicking the
    /// menu when CarPlay is already on would tear down a working
    /// display. Reattaching is the opposite request: the caller is
    /// saying "what's listed is no good". A screen can sit in Connected
    /// Screens with no framebuffer behind it, which is precisely the
    /// state that needs the Disabled → CarPlay cycle, and precisely the
    /// state where the probe says "already connected, nothing to do".
    /// So reattach must not consult it.
    @Test func `reattach cycles the panel even when a screen is already listed`() throws {
        let panel = MockExternalDisplayPanel()
        given(panel).recoverCarPlay().willReturn()
        let external = HostExternalDisplays(
            panel: panel,
            enumerateIO: { self.connectedEnumerate }
        )

        #expect(external.isCarPlayConnected)
        try external.reattachCarPlay()

        verify(panel).recoverCarPlay().called(1)
        verify(panel).enableCarPlay().called(0)
    }

    @Test func `reattach on a device with no external at all still cycles`() throws {
        let panel = MockExternalDisplayPanel()
        given(panel).recoverCarPlay().willReturn()
        let external = HostExternalDisplays(
            panel: panel,
            enumerateIO: { self.phoneOnlyEnumerate }
        )

        try external.reattachCarPlay()

        verify(panel).recoverCarPlay().called(1)
    }

    private final class EnumerateState: @unchecked Sendable {
        var text: String
        init(text: String) { self.text = text }
    }
}
