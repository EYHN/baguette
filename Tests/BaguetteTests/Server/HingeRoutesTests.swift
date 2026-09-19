import Testing
import Foundation
import Mockable
@testable import Baguette

/// `GET /simulators/<udid>/hinge` — what the page polls on a foldable
/// to learn that the pose changed under it, so it can re-bind the
/// stream, the bezel and the tap space to the newly lit panel.
@Suite("Server hinge route")
@MainActor
struct HingeRoutesTests {

    private func wiring(
        deviceType: String, panels: [IntegratedPanel], angle: HingeAngle?,
        orientation: DeviceOrientation? = nil
    ) -> (MockSimulators, MockChromes) {
        let simulators = MockSimulators()
        let sim = MockSimulator()
        let chromes = MockChromes()
        let hinge = MockHinge()
        let displays = MockDisplays()
        let phone = MockDisplay()
        given(simulators).find(udid: .value("U")).willReturn(sim)
        given(simulators).find(udid: .value("nope")).willReturn(nil)
        given(sim).deviceTypeName.willReturn(deviceType)
        given(sim).hinge().willReturn(hinge)
        given(sim).displays().willReturn(displays)
        given(displays).phone.willReturn(phone)
        given(phone).resolve().willReturn(DisplayBinding(
            kind: .phone, connectedScreenId: 3,
            portName: "com.apple.framebuffer.display",
            size: Size(width: 2007, height: 2853), orientation: orientation
        ))
        given(hinge).angle().willReturn(angle)
        given(chromes).panels(forDeviceName: .value(deviceType)).willReturn(panels)
        return (simulators, chromes)
    }

    /// The guest turns the unfolded panel to landscape by itself; the
    /// page did not do it, so it has to be told.
    @Test func `an open foldable reports its angle, the unfolded panel and its orientation`() {
        let (simulators, chromes) = wiring(
            deviceType: "iPhone Duo", panels: [.primary, .secondary],
            angle: HingeAngle(degrees: 130), orientation: .landscapeLeft)
        let json = Server.hingeJSON(udid: "U", simulators: simulators, chromes: chromes)
        #expect(json == #"{"ok":true,"foldable":true,"angleDegrees":130.0,"litPanel":"secondary","orientation":"landscape-left"}"#)
    }

    @Test func `a folded foldable reports the cover`() {
        let (simulators, chromes) = wiring(
            deviceType: "iPhone Duo", panels: [.primary, .secondary],
            angle: HingeAngle(degrees: 3.2), orientation: .portrait)
        let json = Server.hingeJSON(udid: "U", simulators: simulators, chromes: chromes)
        #expect(json == #"{"ok":true,"foldable":true,"angleDegrees":3.2,"litPanel":"primary","orientation":"portrait"}"#)
    }

    /// A reading that did not arrive is reported as such, and the panel
    /// is the one the device boots with.
    @Test func `a foldable with no reading reports a null angle and the cover`() {
        let (simulators, chromes) = wiring(
            deviceType: "iPhone Duo", panels: [.primary, .secondary], angle: nil)
        let json = Server.hingeJSON(udid: "U", simulators: simulators, chromes: chromes)
        #expect(json == #"{"ok":true,"foldable":true,"angleDegrees":null,"litPanel":"primary","orientation":null}"#)
    }

    /// A phone has nothing to poll; the page reads `foldable:false` and
    /// never asks again. Neither its hinge nor its displays are consulted.
    @Test func `a single-panel device is not foldable`() {
        let (simulators, chromes) = wiring(
            deviceType: "iPhone 17 Pro", panels: [.primary], angle: nil)
        let json = Server.hingeJSON(udid: "U", simulators: simulators, chromes: chromes)
        #expect(json == #"{"ok":true,"foldable":false,"angleDegrees":null,"litPanel":"primary","orientation":null}"#)
    }

    @Test func `an unknown udid has no hinge`() {
        let (simulators, chromes) = wiring(
            deviceType: "iPhone Duo", panels: [.primary, .secondary], angle: nil)
        #expect(Server.hingeJSON(udid: "nope", simulators: simulators, chromes: chromes) == nil)
    }
}

/// What the stream socket pushes to the page for each hinge sample, so
/// the page can draw the fold at the angle the runtime is at.
@Suite("Server hinge message")
struct HingeMessageTests {
    @Test func `a sample is a hinge envelope with its angle`() {
        #expect(Server.hingeMessage(HingeAngle(degrees: 130)) == #"{"type":"hinge","angleDegrees":130.0}"#)
        #expect(Server.hingeMessage(HingeAngle(degrees: 3.8)) == #"{"type":"hinge","angleDegrees":3.8}"#)
    }
}
