import Foundation
import IOSurface
import ObjectiveC

/// Production `Screen` — registers SimulatorKit framebuffer callbacks via
/// the ObjC runtime and forwards `IOSurface` frames to the caller as they
/// arrive. Pure pass-through: emits exactly when SimulatorKit composites
/// a new frame and nothing more. Cadence policy (5 fps for MJPEG,
/// 60 fps for H.264, etc.) belongs in the consumer — see `StreamSession`.
///
/// Multi-descriptor: simulators expose secondary planes / overlays. We
/// register on every `com.apple.framebuffer.display` descriptor and pick
/// whichever currently has the largest live surface area each tick.
final class SimulatorKitScreen: Screen, @unchecked Sendable {
    private let udid: String
    private let host: any DeviceHost
    private let queue = DispatchQueue(label: "baguette.screen", qos: .userInteractive)

    private var ioClient: NSObject?
    private var descriptors: [NSObject] = []
    private var callbackUUIDs: [ObjectIdentifier: NSUUID] = [:]
    private var onFrame: (@Sendable (IOSurface) -> Void)?
    private var onMetadata: (@Sendable (ScreenMetadata) -> Void)?

    init(udid: String, host: any DeviceHost) {
        self.udid = udid
        self.host = host
    }

    private func resolveDevice() -> NSObject? {
        host.resolveDevice(udid: udid)
    }

    func start(
        onFrame: @escaping @Sendable (IOSurface) -> Void,
        onMetadata: @escaping @Sendable (ScreenMetadata) -> Void
    ) throws {
        self.onFrame = onFrame
        self.onMetadata = onMetadata

        guard let device = resolveDevice() else {
            throw SimulatorError.notFound(udid: udid)
        }
        guard let io = device.perform(NSSelectorFromString("io"))?
            .takeUnretainedValue() as? NSObject
        else {
            throw ScreenError.ioUnavailable
        }
        ioClient = io
        try wireFramebuffer()
    }

    func stop() {
        let unregSel = NSSelectorFromString("unregisterScreenCallbacksWithUUID:")
        for desc in descriptors {
            if let uuid = callbackUUIDs[ObjectIdentifier(desc)],
               desc.responds(to: unregSel)
            {
                desc.perform(unregSel, with: uuid)
            }
        }
        descriptors.removeAll()
        callbackUUIDs.removeAll()
        ioClient = nil
        onFrame = nil
        onMetadata = nil
    }

    // MARK: - private

    private func wireFramebuffer() throws {
        guard let io = ioClient else { throw ScreenError.ioUnavailable }

        // Lazy ports population.
        io.perform(NSSelectorFromString("updateIOPorts"))

        guard let ports = io.value(forKey: "deviceIOPorts") as? [NSObject] else {
            throw ScreenError.noFramebuffer
        }

        let pidSel = NSSelectorFromString("portIdentifier")
        let descSel = NSSelectorFromString("descriptor")
        let surfSel = NSSelectorFromString("framebufferSurface")

        var candidates: [NSObject] = []
        for port in ports where port.responds(to: pidSel) {
            guard let pid = port.perform(pidSel)?.takeUnretainedValue(),
                  "\(pid)" == "com.apple.framebuffer.display",
                  port.responds(to: descSel),
                  let desc = port.perform(descSel)?.takeUnretainedValue() as? NSObject,
                  desc.responds(to: surfSel)
            else { continue }
            candidates.append(desc)
        }
        guard !candidates.isEmpty else { throw ScreenError.noFramebuffer }
        descriptors = candidates

        for desc in candidates {
            try registerCallbacks(on: desc)
        }
    }

    private func registerCallbacks(on desc: NSObject) throws {
        let regSel = NSSelectorFromString(
            "registerScreenCallbacksWithUUID:callbackQueue:frameCallback:" +
                "surfacesChangedCallback:propertiesChangedCallback:"
        )
        guard desc.responds(to: regSel) else { throw ScreenError.callbackUnavailable }

        let uuid = NSUUID()
        callbackUUIDs[ObjectIdentifier(desc)] = uuid

        let frame: @convention(block) () -> Void = { [weak self] in
            self?.enqueueLatestFrame()
        }
        let surfaces: @convention(block) () -> Void = { [weak self] in
            self?.enqueueLatestFrame()
        }
        let props: @convention(block) (AnyObject?) -> Void = { [weak self] _ in
            self?.enqueueLatestMetadata()
        }

        guard let imp = class_getMethodImplementation(type(of: desc), regSel) else {
            throw ScreenError.callbackUnavailable
        }
        typealias Fn = @convention(c) (
            AnyObject, Selector, AnyObject, AnyObject, AnyObject, AnyObject, AnyObject
        ) -> Void
        unsafeBitCast(imp, to: Fn.self)(
            desc, regSel,
            uuid, queue as AnyObject,
            frame as AnyObject, surfaces as AnyObject, props as AnyObject
        )
    }

    private func enqueueLatestFrame() {
        queue.async { [weak self] in
            self?.captureLatest()
        }
    }

    private func enqueueLatestMetadata() {
        queue.async { [weak self] in
            self?.captureLatestMetadata()
        }
    }

    /// Picks the descriptor whose live surface has the largest area —
    /// secondary planes / overlays are typically smaller than the main
    /// screen — and forwards its IOSurface and authoritative properties.
    private func captureLatest() {
        guard let latest = latestFramebuffer() else { return }
        onMetadata?(metadata(for: latest.descriptor))
        onFrame?(latest.surface)
    }

    /// Property callbacks do not imply new pixels. Publish metadata from the
    /// same selected descriptor without manufacturing a framebuffer event.
    private func captureLatestMetadata() {
        guard let latest = latestFramebuffer() else { return }
        onMetadata?(metadata(for: latest.descriptor))
    }

    private func latestFramebuffer() -> (surface: IOSurface, descriptor: NSObject)? {
        let surfSel = NSSelectorFromString("framebufferSurface")
        var best: (surface: IOSurface, descriptor: NSObject)?
        var bestArea = 0
        for desc in descriptors {
            guard let surfObj = desc.perform(surfSel)?.takeUnretainedValue() else { continue }
            let surf = unsafeDowncast(surfObj, to: IOSurface.self)
            let area = IOSurfaceGetWidth(surf) * IOSurfaceGetHeight(surf)
            if area > bestArea {
                best = (surf, desc)
                bestArea = area
            }
        }
        return best
    }

    private func metadata(for descriptor: NSObject) -> ScreenMetadata {
        let propertiesSelector = NSSelectorFromString("screenProperties")
        let orientationSelector = NSSelectorFromString("uiOrientation")
        guard descriptor.responds(to: propertiesSelector),
              let properties = descriptor.perform(propertiesSelector)?
              .takeUnretainedValue() as? NSObject,
              properties.responds(to: orientationSelector),
              let rawValue = properties.value(forKey: "uiOrientation") as? NSNumber
        else {
            return ScreenMetadata(uiOrientation: nil)
        }
        return ScreenMetadata(
            uiOrientation: ScreenOrientation(
                simulatorKitRawValue: rawValue.intValue
            )
        )
    }
}

enum ScreenError: Error, Equatable {
    case ioUnavailable
    case noFramebuffer
    case callbackUnavailable
}
