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
        lit: IntegratedPanel? = nil,
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
        given(sim).litPanel().willReturn(lit)
        given(chromes).panels(forDeviceName: .value(deviceType)).willReturn(panels)
        return (simulators, chromes)
    }

    /// The guest turns the unfolded panel to landscape by itself; the
    /// page did not do it, so it has to be told.
    @Test func `should report an open foldable's angle, its unfolded panel and that panel's orientation`() {
        let (simulators, chromes) = wiring(
            deviceType: "iPhone Duo", panels: [.primary, .secondary],
            angle: HingeAngle(degrees: 130), lit: .secondary, orientation: .landscapeLeft)
        let json = Server.hingeJSON(udid: "U", simulators: simulators, chromes: chromes)
        #expect(json == #"{"ok":true,"foldable":true,"angleDegrees":130.0,"litPanel":"secondary","orientation":"landscape-left"}"#)
    }

    @Test func `should report the cover as the lit panel when the foldable is folded`() {
        let (simulators, chromes) = wiring(
            deviceType: "iPhone Duo", panels: [.primary, .secondary],
            angle: HingeAngle(degrees: 3.2), lit: .primary, orientation: .portrait)
        let json = Server.hingeJSON(udid: "U", simulators: simulators, chromes: chromes)
        #expect(json == #"{"ok":true,"foldable":true,"angleDegrees":3.2,"litPanel":"primary","orientation":"portrait"}"#)
    }

    /// The angle and the panel are two facts. The pose provider lights
    /// the unfolded panel at 30° on the way shut and the cover at 30° on
    /// a fresh boot; the page is told what Core Device says, whatever
    /// the angle.
    @Test func `the lit panel is Core Device's answer, not read off the angle`() {
        let (simulators, chromes) = wiring(
            deviceType: "iPhone Duo", panels: [.primary, .secondary],
            angle: HingeAngle(degrees: 30), lit: .secondary, orientation: .landscapeLeft)
        let json = Server.hingeJSON(udid: "U", simulators: simulators, chromes: chromes)
        #expect(json == #"{"ok":true,"foldable":true,"angleDegrees":30.0,"litPanel":"secondary","orientation":"landscape-left"}"#)
    }

    /// A reading that did not arrive is reported as such, and the panel
    /// is the one the device boots with.
    @Test func `should report a null angle and the cover when the foldable has no hinge reading`() {
        let (simulators, chromes) = wiring(
            deviceType: "iPhone Duo", panels: [.primary, .secondary], angle: nil)
        let json = Server.hingeJSON(udid: "U", simulators: simulators, chromes: chromes)
        #expect(json == #"{"ok":true,"foldable":true,"angleDegrees":null,"litPanel":"primary","orientation":null}"#)
    }

    /// A phone has nothing to poll; the page reads `foldable:false` and
    /// never asks again. Neither its hinge nor its displays are consulted.
    @Test func `should report a single-panel device as not foldable`() {
        let (simulators, chromes) = wiring(
            deviceType: "iPhone 17 Pro", panels: [.primary], angle: nil)
        let json = Server.hingeJSON(udid: "U", simulators: simulators, chromes: chromes)
        #expect(json == #"{"ok":true,"foldable":false,"angleDegrees":null,"litPanel":"primary","orientation":null}"#)
    }

    @Test func `should find no hinge when the udid is unknown`() {
        let (simulators, chromes) = wiring(
            deviceType: "iPhone Duo", panels: [.primary, .secondary], angle: nil)
        #expect(Server.hingeJSON(udid: "nope", simulators: simulators, chromes: chromes) == nil)
    }
}

/// What the stream socket pushes to the page for each hinge sample, so
/// the page can draw the fold at the angle the runtime is at.
@Suite("Server hinge message")
struct HingeMessageTests {
    @Test func `should push each hinge sample to the page as a hinge envelope with its angle`() {
        #expect(Server.hingeMessage(HingeAngle(degrees: 130)) == #"{"type":"hinge","angleDegrees":130.0}"#)
        #expect(Server.hingeMessage(HingeAngle(degrees: 3.8)) == #"{"type":"hinge","angleDegrees":3.8}"#)
    }
}


/// `POST /simulators/<udid>/hinge?pose=open` — the hinge driven from the
/// page's picker, the CLI or a script. Pure dispatch, every branch.
@Suite("Server hinge drive")
struct HingeDriveRoutesTests {
    @Test func `should sweep the hinge to a named pose over Device Hub's default duration`() throws {
        let host = MockSimulators(), sim = MockSimulator(), hinge = MockHinge()
        given(host).find(udid: .value("U")).willReturn(sim)
        given(sim).hinge().willReturn(hinge)
        given(hinge).fold(to: .any, over: .any).willReturn()

        #expect(Server.driveHinge(udid: "U", pose: "open", angle: nil, duration: nil, simulators: host) == .ok)
        verify(hinge).fold(to: .value(130), over: .value(HingeCommand.defaultDuration)).called(1)
    }

    @Test func `should report a bad pose, an unknown device and an undrivable hinge each as its own outcome`() {
        let host = MockSimulators(), sim = MockSimulator(), hinge = MockHinge()
        given(host).find(udid: .value("U")).willReturn(sim)
        given(host).find(udid: .value("ghost")).willReturn(nil)
        given(sim).hinge().willReturn(hinge)
        given(hinge).fold(to: .any, over: .any).willThrow(HingeError.toolMissing)

        #expect(Server.driveHinge(udid: "U", pose: "tent", angle: nil, duration: nil, simulators: host)
            == .invalid(HingeCommandError.unknownPose("tent")))
        #expect(Server.driveHinge(udid: "ghost", pose: "open", angle: nil, duration: nil, simulators: host)
            == .unknownDevice)
        #expect(Server.driveHinge(udid: "U", pose: nil, angle: "90", duration: nil, simulators: host)
            == .failed(HingeError.toolMissing))
    }

    /// The 3D socket refuses a `set_pose` it cannot play as `POST /hinge`
    /// does, rather than as a bad camera.
    @Test func `should answer a pose the 3D socket cannot play with what was wrong with it`() {
        #expect(Server.poseErrorFrame(.invalidDuration)
            == #"{"ok":false,"error":"duration must be a number of seconds from 0 to 60"}"#)
        #expect(Server.poseErrorFrame(.angleOutOfRange)
            == #"{"ok":false,"error":"angle must be a number from 0 to 180"}"#)
    }

    @Test func `should leave the hinge move unconfirmed when the helper times out`() {
        let host = MockSimulators(), sim = MockSimulator(), hinge = MockHinge()
        given(host).find(udid: .value("U")).willReturn(sim)
        given(sim).hinge().willReturn(hinge)
        given(hinge).fold(to: .any, over: .any).willThrow(HingeError.toolTimedOut)

        #expect(Server.driveHinge(udid: "U", pose: "flat", angle: nil, duration: nil, simulators: host) == .unconfirmed)
    }
}
