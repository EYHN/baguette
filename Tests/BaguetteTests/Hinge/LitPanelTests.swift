import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// Which of a simulator's panels the chrome, screen and tap space
/// describe. On a foldable that is Core Device's call — never the
/// hinge angle's; everything else has one panel and never asks.
@Suite("Simulator lit panel")
struct LitPanelTests {

    private func duo(lit: IntegratedPanel?) -> (MockSimulator, MockChromes) {
        let sim = MockSimulator()
        let chromes = MockChromes()
        given(sim).deviceTypeName.willReturn("iPhone Duo")
        given(sim).litPanel().willReturn(lit)
        given(chromes).panels(forDeviceName: .value("iPhone Duo")).willReturn([.primary, .secondary])
        return (sim, chromes)
    }

    @Test func `the cover is lit when Core Device says so`() {
        let (sim, chromes) = duo(lit: .primary)
        #expect(sim.litPanel(in: chromes) == .primary)
    }

    @Test func `the unfolded panel is lit when Core Device says so`() {
        let (sim, chromes) = duo(lit: .secondary)
        #expect(sim.litPanel(in: chromes) == .secondary)
    }

    /// No answer means as booted: folded.
    @Test func `without an answer the cover is lit`() {
        let (sim, chromes) = duo(lit: nil)
        #expect(sim.litPanel(in: chromes) == .primary)
    }

    /// The hinge angle is not what lights a panel: the runtime's pose
    /// provider weighs speed and history, and an app may claim the
    /// cover while open. It is not consulted at all.
    @Test func `the hinge angle is never asked`() {
        let (sim, chromes) = duo(lit: .secondary)
        _ = sim.litPanel(in: chromes)
        verify(sim).hinge().called(0)
    }

    /// Core Device's read is a devicectl round-trip; a phone must not pay it.
    @Test func `a single-panel device never asks`() {
        let sim = MockSimulator()
        let chromes = MockChromes()
        given(sim).deviceTypeName.willReturn("iPhone 17 Pro")
        given(chromes).panels(forDeviceName: .any).willReturn([.primary])
        #expect(sim.litPanel(in: chromes) == .primary)
        verify(sim).litPanel().called(0)
        verify(sim).hinge().called(0)
    }

    @Test func `the chrome is the lit panel's`() {
        let (sim, chromes) = duo(lit: .secondary)
        let unfolded = DeviceChromeAssets(
            chrome: DeviceChrome(
                identifier: "phone14",
                screenInsets: Insets(top: 0, left: 0, bottom: 0, right: 0),
                outerCornerRadius: 0, buttons: [],
                compositeImageName: "X"
            ),
            composite: ChromeImage(data: Data(), size: Size(width: 1, height: 1))
        )
        given(chromes).assets(forDeviceName: .value("iPhone Duo"), panel: .value(.secondary))
            .willReturn(unfolded)
        #expect(sim.chrome(in: chromes)?.chrome.identifier == "phone14")
    }
}

/// The panels of a device type, by the names Connected Screens gives
/// them: capabilities order, the first being the one every device has.
@Suite("DisplayPanels ↔ IntegratedPanel")
struct DisplayPanelNamingTests {
    private let cover = DisplayPanel(screenID: 1, pixelSize: CGSize(width: 1398, height: 2034), scale: 3, nativeRotation: 0)
    private let inner = DisplayPanel(screenID: 3, pixelSize: CGSize(width: 2007, height: 2853), scale: 3, nativeRotation: 270)

    @Test func `the first panel is primary and the second is the unfolded one`() {
        let panels = DisplayPanels(panels: [cover, inner])
        #expect(panels.integratedPanel(cover) == .primary)
        #expect(panels.integratedPanel(inner) == .secondary)
        #expect(panels.panel(.primary) == cover)
        #expect(panels.panel(.secondary) == inner)
    }

    @Test func `a phone has no unfolded panel`() {
        let panels = DisplayPanels(panels: [cover])
        #expect(panels.panel(.secondary) == nil)
        #expect(panels.integratedPanel(inner) == nil)
    }
}
