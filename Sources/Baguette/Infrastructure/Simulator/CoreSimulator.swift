import Foundation
import ObjectiveC

/// Production `Simulator` — owns identity + state plus the verbs that
/// touch the booted iOS guest. Resolves a fresh `SimDevice` via
/// `host.resolveDevice(udid:)` on each operation so we never act on a
/// stale `NSObject` (CoreSimulator returns a new one when state
/// changes; clients that cached the first ref get hit with `EBADF`-ish
/// errors on subsequent calls).
///
/// Constructed by `CoreSimulators.all` — this type is the only place
/// in the codebase that knows about CoreSimulator's `bootWithError:` /
/// `shutdownWithError:` selectors, and the only place that hands raw
/// UDIDs to `SimulatorKitScreen` / `IndigoHIDInput` /
/// `AXPTranslatorAccessibility` / `SimDeviceLogStream` /
/// `PurpleEventOrientation`.
final class CoreSimulator: Simulator, @unchecked Sendable {
    let udid: String
    let name: String
    let state: SimulatorState
    let runtime: String
    let deviceTypeName: String

    private let host: any DeviceHost

    init(
        udid: String,
        name: String,
        state: SimulatorState,
        runtime: String,
        deviceTypeName: String,
        host: any DeviceHost
    ) {
        self.udid = udid
        self.name = name
        self.state = state
        self.runtime = runtime
        self.deviceTypeName = deviceTypeName
        self.host = host
    }

    func boot() throws {
        guard let device = host.resolveDevice(udid: udid) else {
            throw SimulatorError.notFound(udid: udid)
        }

        // Try bootWithOptions:error: first (headless boot, persists past disconnect).
        let bootOpts = NSSelectorFromString("bootWithOptions:error:")
        if device.responds(to: bootOpts) {
            var err: NSError?
            let opts: NSDictionary = ["persist": true]
            if invokeBoolWithObjAndError(device, bootOpts, opts, &err) { return }
            if let err { logErr("bootWithOptions failed: \(err)") }
        }

        let bootSel = NSSelectorFromString("bootWithError:")
        if device.responds(to: bootSel) {
            var err: NSError?
            if invokeBoolWithError(device, bootSel, &err) { return }
            if let err { logErr("bootWithError failed: \(err)") }
        }

        throw SimulatorError.bootFailed
    }

    func shutdown() throws {
        guard let device = host.resolveDevice(udid: udid) else {
            throw SimulatorError.notFound(udid: udid)
        }
        let sel = NSSelectorFromString("shutdownWithError:")
        guard device.responds(to: sel) else { throw SimulatorError.shutdownFailed }
        var err: NSError?
        guard invokeBoolWithError(device, sel, &err) else {
            if let err { logErr("shutdownWithError failed: \(err)") }
            throw SimulatorError.shutdownFailed
        }
    }

    /// The device's own plane, bound before use.
    ///
    /// These used to open an unbound `SimulatorKitScreen` (largest
    /// surface each tick) and an `IndigoHIDInput` on the built-in slot.
    /// Both are right on a single-panel device and both are wrong on a
    /// foldable: iPhone Duo's largest surface and its built-in slot are
    /// the unfolded panel, dark while folded. Going through the phone
    /// `Display` binds the panel Connected Screens names `primary` for
    /// the framebuffer, and — only when there are several panels —
    /// addresses that panel's own digitizer. See `SimulatorKitDisplay`.
    func screen() -> any Screen {
        displays().phone.screen()
    }

    func input() -> any Input {
        displays().phone.input()
    }

    func displays() -> any Displays {
        SimulatorKitDisplays(udid: udid, host: host, hinge: hinge(), keys: GuestHingeMotor.forDevice(udid))
    }

    /// One monitor per device: sockets share a watch and binds read the
    /// last sample while it runs. See `SharedHinge`.
    func hinge() -> any Hinge {
        SharedHinge.forDevice(udid, make: { DevicectlHinge(udid: udid) }, motor: GuestHingeMotor.forDevice(udid))
    }

    func externalDisplays() -> any ExternalDisplays {
        HostExternalDisplays(udid: udid)
    }

    func accessibility() -> any Accessibility {
        AXPTranslatorAccessibility(
            udid: udid, host: host,
            litPanelPointSize: { [udid, host] in
                // Only a foldable has a panel to choose; a phone keeps the
                // device type's `mainScreenSize` and pays no round-trip.
                guard let sized = try? SimulatorKitFramebufferPorts.sizedPorts(udid: udid, host: host),
                      IntegratedPanels.several(in: sized),
                      let binding = try? SimulatorKitDisplays(
                          udid: udid, host: host,
                          hinge: SharedHinge.forDevice(udid) { DevicectlHinge(udid: udid) }
                      ).phone.resolve(),
                      let scale = Self.mainScreenScale(udid: udid, host: host),
                      let size = binding.pointSize(scale: scale)
                else { return nil }
                return CGSize(width: size.width, height: size.height)
            }
        )
    }

    /// `deviceType.mainScreenScale` — the same number for every panel
    /// of a device (iPhone Duo is @3x on both).
    private static func mainScreenScale(udid: String, host: any DeviceHost) -> Double? {
        guard let device = host.resolveDevice(udid: udid),
              let deviceType = device.value(forKey: "deviceType") as? NSObject,
              let scale = (deviceType.value(forKey: "mainScreenScale") as? NSNumber)?.doubleValue,
              scale > 0
        else { return nil }
        return scale
    }

    func logs() -> any LogStream {
        SimDeviceLogStream(udid: udid, host: host)
    }

    func orientation() -> any Orientation {
        PurpleEventOrientation(udid: udid, host: host)
    }

    func statusBar() -> any StatusBar {
        SimctlStatusBar(udid: udid)
    }

    func interface() -> any Interface {
        SimctlInterface(udid: udid)
    }

    func location() -> any Location {
        SimctlLocation(udid: udid)
    }

    func shake() -> any Shake {
        SimctlShake(udid: udid)
    }

    /// Resolves the bundled `VirtualMotion.dylib` on the way through, since
    /// publishing an intent is useless without the dylib that reads it. A
    /// build that doesn't ship the dylib yields a handle whose `publish`
    /// throws `MotionError.dylibMissing` rather than silently doing nothing.
    func motion() -> any Motion {
        SharedFileMotion(
            fileURL: URL(fileURLWithPath: SharedFileMotion.path(forUDID: udid)),
            dylibPath: InjectedDylibInstaller.installIfNeeded(.motion),
            injection: SimctlSimulatorInjection()
        )
    }

    /// Resolves the bundled `VirtualNetwork.dylib` on the way through, since
    /// publishing a condition is useless without the dylib that applies it.
    /// A build that doesn't ship the dylib yields a handle whose `apply`
    /// throws `NetworkError.dylibMissing` rather than silently doing nothing
    /// — which for a throttle would be indistinguishable from working.
    func network() -> any Network {
        SharedFileNetwork(
            fileURL: URL(fileURLWithPath: SharedFileNetwork.path(forUDID: udid)),
            dylibPath: InjectedDylibInstaller.installIfNeeded(.network),
            injection: SimctlSimulatorInjection()
        )
    }

    func pasteboard() -> any Pasteboard {
        SimctlPasteboard(udid: udid)
    }

    func apps() -> any Apps {
        SimctlApps(udid: udid)
    }

    func photos() -> any PhotoLibrary {
        SimctlPhotoLibrary(udid: udid)
    }

    func watchPairing() -> any WatchPairing {
        SimctlWatchPairing(udid: udid)
    }
}
