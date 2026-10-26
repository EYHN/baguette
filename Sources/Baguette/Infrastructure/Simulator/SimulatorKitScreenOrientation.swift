import Foundation
import ObjectiveC

/// Reads the guest's current interface rotation, including rejected
/// device rotations. `simctl io enumerate` omits it on older Xcodes.
enum SimulatorKitScreenOrientation {
    static func read(device: NSObject, screenID: UInt32) throws -> DeviceOrientation {
        try read(properties: properties(device: device, screenID: screenID), rotates: rotates(device))
    }

    static func readScreen(device: NSObject, screenID: UInt32, panel: IntegratedPanel?) throws -> AXScreen {
        try readScreen(
            properties: properties(device: device, screenID: screenID), panel: panel, rotates: rotates(device))
    }

    /// Whether the device's interface can turn on its panel. Only iPhone
    /// and iPad rotate; an Apple Watch (and Apple TV, Vision) never
    /// reports an interface orientation — SimulatorKit leaves it 0 for
    /// the device's whole life — and its panel is always presented
    /// unturned. An unreadable family counts as rotating, so the
    /// orientation stays required.
    static func rotates(_ device: NSObject) -> Bool {
        guard let type = device.value(forKey: "deviceType") as? NSObject,
            let family = type.value(forKey: "productFamily") as? String
        else { return true }
        return rotates(productFamily: family)
    }

    static func rotates(productFamily: String) -> Bool {
        productFamily == "iPhone" || productFamily == "iPad"
    }

    private static func properties(device: NSObject, screenID: UInt32) throws -> NSObject {
        // The framebuffer port's own snapshot first: it is safe off the
        // main thread, which `SimDeviceScreen` is not in a library host.
        if let properties = SimulatorKitFramebufferPorts.screenProperties(device: device, screenID: screenID) {
            return properties
        }
        return try screenProperties(device: device, screenID: screenID)
    }

    private static func screenProperties(device: NSObject, screenID: UInt32) throws -> NSObject {
        let allocSelector = NSSelectorFromString("alloc")
        let initSelector = NSSelectorFromString("initWithDevice:screenID:")
        guard let cls = NSClassFromString("SimulatorKit.SimDeviceScreen"),
            let alloc = class_getClassMethod(cls, allocSelector),
            let initialize = class_getInstanceMethod(cls, initSelector)
        else { throw Failure.unavailable }

        // IMP calls do not carry ObjC's alloc/init ownership annotations.
        // Transfer the +1 allocation through init, then adopt it exactly once.
        typealias Allocate = @convention(c) (AnyClass, Selector) -> Unmanaged<NSObject>?
        guard let instance = unsafeBitCast(method_getImplementation(alloc), to: Allocate.self)(cls, allocSelector)
        else { throw Failure.unavailable }

        typealias Initialize = @convention(c) (Unmanaged<NSObject>, Selector, AnyObject, UInt32) -> Unmanaged<NSObject>?
        guard
            let display = unsafeBitCast(method_getImplementation(initialize), to: Initialize.self)(
                instance, initSelector, device, screenID)?.takeRetainedValue(),
            let screen = object(display, selector: "screen"),
            let properties = object(screen, selector: "screenProperties")
        else { throw Failure.unavailable }
        return properties
    }

    /// Each property comes from this fresh immutable screenProperties snapshot.
    static func readScreen(properties: NSObject, panel: IntegratedPanel?, rotates: Bool = true) throws -> AXScreen {
        let sizeSelector = NSSelectorFromString("pixelSize")
        let idSelector = NSSelectorFromString("screenID")
        let scaleSelector = NSSelectorFromString("preferredUIScale")
        guard properties.responds(to: sizeSelector), properties.responds(to: idSelector),
            let sizeMethod = properties.method(for: sizeSelector),
            let idMethod = properties.method(for: idSelector),
            let mode = object(properties, selector: "currentMode"),
            mode.responds(to: scaleSelector), let scaleMethod = mode.method(for: scaleSelector)
        else { throw Failure.unavailable }
        typealias ReadSize = @convention(c) (AnyObject, Selector) -> CGSize
        typealias ReadID = @convention(c) (AnyObject, Selector) -> UInt32
        typealias ReadScale = @convention(c) (AnyObject, Selector) -> Double
        let size = unsafeBitCast(sizeMethod, to: ReadSize.self)(properties, sizeSelector)
        let id = unsafeBitCast(idMethod, to: ReadID.self)(properties, idSelector)
        let scale = unsafeBitCast(scaleMethod, to: ReadScale.self)(mode, scaleSelector)
        guard scale.isFinite, scale > 0, size.width.isFinite, size.height.isFinite,
            size.width > 0, size.height > 0,
            (size.width / scale).isFinite, (size.height / scale).isFinite
        else { throw Failure.unavailable }
        return AXScreen(
            width: size.width / scale, height: size.height / scale,
            orientation: try read(properties: properties, rotates: rotates),
            target: ScreenTarget(
                screenId: id, litPanel: panel,
                pixelSize: Size(width: size.width, height: size.height)))
    }

    /// `rotates` is false for a device whose interface never turns: its
    /// unset orientation (0) is the unturned panel, not an unknown one.
    static func read(properties: NSObject, rotates: Bool = true) throws -> DeviceOrientation {
        let selector = NSSelectorFromString("uiOrientation")
        guard properties.responds(to: selector), let method = properties.method(for: selector) else {
            throw Failure.unavailable
        }
        typealias Read = @convention(c) (AnyObject, Selector) -> UInt32
        let raw = unsafeBitCast(method, to: Read.self)(properties, selector)
        // SimulatorKit's landscape values are opposite to the guest's
        // UIWindowScene values and baguette's device-orientation wire.
        switch raw {
        case 1: return .portrait
        case 2: return .portraitUpsideDown
        case 3: return .landscapeLeft
        case 4: return .landscapeRight
        case 0 where !rotates: return .portrait
        default: throw Failure.unknown(raw)
        }
    }

    private static func object(_ target: NSObject, selector name: String) -> NSObject? {
        let selector = NSSelectorFromString(name)
        guard target.responds(to: selector), let method = target.method(for: selector) else { return nil }
        // ROCK proxies forward selectors but do not implement these KVC keys.
        typealias Read = @convention(c) (AnyObject, Selector) -> AnyObject?
        return unsafeBitCast(method, to: Read.self)(target, selector) as? NSObject
    }

    enum Failure: LocalizedError, Equatable {
        case unavailable
        case unknown(UInt32)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return
                    "SimulatorKit cannot report the screen's interface orientation; coordinate conversion is unavailable."
            case .unknown(0):
                // The guest has not published its interface orientation:
                // it is still booting, or its display service is not up.
                return
                    "The simulator has not reported its interface orientation yet, so on-screen positions are unknown. "
                    + "Wait for it to finish booting and retry; if this persists, reboot the simulator."
            case .unknown(let raw):
                return
                    "SimulatorKit reported unknown interface orientation \(raw); coordinate conversion is unavailable."
            }
        }
    }
}
