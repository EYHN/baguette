import Foundation
import IOSurface
import ObjectiveC
import Darwin

private typealias UInt32Getter = @convention(c) (AnyObject, Selector) -> UInt32

private let sendUInt32Message: UInt32Getter = {
    let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")!
    return unsafeBitCast(symbol, to: UInt32Getter.self)
}()

func invokeUInt32Getter(_ target: NSObject, _ selector: Selector) -> UInt32? {
    guard target.responds(to: selector) else { return nil }
    return sendUInt32Message(target, selector)
}

/// Production `Screen` — registers SimulatorKit framebuffer callbacks via
/// the ObjC runtime and forwards `IOSurface` frames to the caller as they
/// arrive. Pure pass-through: emits exactly when SimulatorKit composites
/// a new frame and nothing more. Cadence policy (5 fps for MJPEG,
/// 60 fps for H.264, etc.) belongs in the consumer — see `StreamSession`.
///
/// Multi-descriptor: simulators expose secondary planes / overlays. We
/// register on every `com.apple.framebuffer.display` descriptor and pick
/// a surface each tick — largest area by default, or the plane closest
/// to an optional `DisplayBinding` size when one is supplied.
final class SimulatorKitScreen: Screen, @unchecked Sendable {
    private let udid: String
    private let host: any DeviceHost
    private let binding: DisplayBinding?
    private let queue = DispatchQueue(label: "baguette.screen", qos: .userInteractive)

    private var ioClient: NSObject?
    private var descriptors: [NSObject] = []
    private var callbackUUIDs: [ObjectIdentifier: NSUUID] = [:]
    private var onFrame: (@Sendable (IOSurface) -> Void)?
    private var onMetadata: (@Sendable (ScreenMetadata) -> Void)?
    private var idleTimer: DispatchSourceTimer?
    /// Guards against queueing duplicate captures — see `scheduleCapture`.
    /// Only ever touched on `queue`, which is serial.
    private var pending = PendingCapture()
    /// The device's integrated panels, read once at `start`. More than
    /// one means a foldable, and the plane to stream is whichever panel
    /// it is presenting on (`ActiveDisplays`), not the largest surface.
    private var panels = DisplayPanels(panels: [])

    /// One integrated panel's current surface.
    struct PanelSurface {
        let panel: DisplayPanel
        /// The panel by its Connected Screens name (`DisplayPanels.integratedPanel`).
        let name: IntegratedPanel
        let surface: IOSurface
    }

    /// Set before `start` by a consumer that wants a foldable's panels all
    /// at once — lit or not — instead of the one it is presenting on. When
    /// set, a foldable's frames arrive here and `onFrame` stays quiet; any
    /// other device is unaffected. The second argument is the presenting
    /// panel, when Core Device has said which.
    var onPanels: (@Sendable ([PanelSurface], DisplayPanel?) -> Void)?

    init(udid: String, host: any DeviceHost, binding: DisplayBinding? = nil) {
        self.udid = udid
        self.host = host
        self.binding = binding
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
        // The phone plane — bound by `SimulatorKitDisplay` to the panel lit
        // at bind time, or unbound — follows the hinge from here on; a
        // CarPlay or external plane has no panels to follow.
        if (binding?.kind ?? .phone) == .phone {
            panels = ActiveDisplays.panels(of: device)
            if panels.isFoldable {
                // Each answer re-emits a frame: the newly presenting panel
                // may be showing a static screen that composites nothing.
                ActiveDisplays.shared.beginWatching(udid: udid, owner: self) { [weak self] in
                    self?.queue.async { self?.scheduleCapture() }
                }
            }
        }
        try wireFramebuffer()
        startIdleFloorIfNeeded()
    }

    func stop() {
        idleTimer?.cancel()
        idleTimer = nil
        if panels.isFoldable { ActiveDisplays.shared.endWatching(udid: udid, owner: self) }
        panels = DisplayPanels(panels: [])
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

    private func startIdleFloorIfNeeded() {
        let kind = binding?.kind ?? .phone
        guard ScreenIdleFloor.isEnabled(for: kind) else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now(),
            repeating: .nanoseconds(Int(ScreenIdleFloor.intervalNanoseconds))
        )
        timer.setEventHandler { [weak self] in
            self?.scheduleCapture()
        }
        timer.resume()
        idleTimer = timer
    }

    private func wireFramebuffer() throws {
        guard let io = ioClient else { throw ScreenError.ioUnavailable }

        var         candidates = findFramebufferDescriptors(io: io)
        if IOPortsRefresh.shouldUpdate(hasFramebufferDisplayPorts: !candidates.isEmpty) {
            io.perform(NSSelectorFromString("updateIOPorts"))
            candidates = findFramebufferDescriptors(io: io)
        }
        guard !candidates.isEmpty else { throw ScreenError.noFramebuffer }
        descriptors = candidates

        for desc in candidates {
            try registerCallbacks(on: desc)
        }
        // Surfaces often populate only after callbacks are registered —
        // pull once now and let the idle floor keep pulling.
        queue.async { [weak self] in self?.scheduleCapture() }
    }

    private func findFramebufferDescriptors(io: NSObject) -> [NSObject] {
        guard let ports = io.value(forKey: "deviceIOPorts") as? [NSObject] else {
            return []
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
        return candidates
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
            self?.scheduleCapture()
        }
        let surfaces: @convention(block) () -> Void = { [weak self] in
            self?.scheduleCapture()
        }
        let props: @convention(block) (AnyObject?) -> Void = { [weak self] _ in
            self?.scheduleMetadataCapture()
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

    /// Queue a capture unless one is already waiting to run.
    ///
    /// Registered callbacks are delivered on `queue`, so this is serial with
    /// the capture itself. Without the coalescer, a composite rate above the
    /// capture rate enqueues duplicates without bound — each one paying a
    /// synchronous XPC round-trip for `framebufferSurface` and its share of
    /// autorelease churn — and the process runs away rather than degrading.
    private func scheduleCapture() {
        guard pending.request() else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.pending.begin()
            self.captureLatest()
        }
    }

    /// Property callbacks are rare (orientation flips, scale changes) and do
    /// not imply new pixels, so they bypass the frame coalescer and publish
    /// metadata directly without manufacturing a framebuffer event.
    private func scheduleMetadataCapture() {
        queue.async { [weak self] in
            self?.captureLatestMetadata()
        }
    }

    /// Picks the descriptor for this screen's plane and forwards its
    /// IOSurface and authoritative properties. CarPlay bindings never
    /// fall back to the phone plane — missing external surfaces emit
    /// nothing. Drains its own autorelease pool.
    ///
    /// `framebufferSurface` forwards through ROCKit to CoreSimulatorService,
    /// and that round-trip leaves XPC replies, dispatch groups and the
    /// IOSurface itself autoreleased. At frame rate, across several streams,
    /// those temporaries are the bulk of the process's allocation — so the
    /// pool is drained per capture rather than left to whatever pool the
    /// enclosing work item happens to provide.
    ///
    /// The body is a separate method on purpose: `return` inside an
    /// `autoreleasepool { }` closure returns from the *closure*, so inlining
    /// the guards below would quietly change their control flow.
    private func captureLatest() {
        autoreleasepool { performCapture() }
    }

    private func performCapture() {
        guard let latest = latestFramebuffer() else { return }
        onMetadata?(metadata(for: latest.descriptor, panel: latest.panel))
        if let onPanels, panels.isFoldable {
            onPanels(panelSurfaces(among: latest.surfaces), latest.panel)
        } else {
            onFrame?(latest.surface)
        }
    }

    /// Every integrated panel's surface, out of the surfaces this capture
    /// already fetched. Panels differ in size, which is what tells their
    /// framebuffer ports apart.
    private func panelSurfaces(among surfaces: [IOSurface]) -> [PanelSurface] {
        panels.panels.compactMap { panel in
            surfaces.first {
                IOSurfaceGetWidth($0) == Int(panel.pixelSize.width)
                    && IOSurfaceGetHeight($0) == Int(panel.pixelSize.height)
            }.map { PanelSurface(panel: panel, name: panels.integratedPanel(panel) ?? .primary, surface: $0) }
        }
    }

    /// See `scheduleMetadataCapture` — same descriptor pick as a frame
    /// capture, metadata only. Reads `framebufferSurface` (an XPC
    /// round-trip), so it drains its own pool too.
    private func captureLatestMetadata() {
        autoreleasepool {
            guard let latest = latestFramebuffer() else { return }
            onMetadata?(metadata(for: latest.descriptor, panel: latest.panel))
        }
    }

    private func latestFramebuffer() -> (surface: IOSurface, descriptor: NSObject, panel: DisplayPanel?, surfaces: [IOSurface])? {
        let surfSel = NSSelectorFromString("framebufferSurface")
        var candidates: [(surface: IOSurface, descriptor: NSObject, size: Size)] = []
        for desc in descriptors {
            guard let surfObj = desc.perform(surfSel)?.takeUnretainedValue() else { continue }
            let surf = unsafeDowncast(surfObj, to: IOSurface.self)
            let w = IOSurfaceGetWidth(surf)
            let h = IOSurfaceGetHeight(surf)
            guard w > 0, h > 0 else { continue }
            candidates.append((surf, desc, Size(width: Double(w), height: Double(h))))
        }
        // A foldable keeps a surface on both panels, so size says nothing
        // about which one is live; the presenting panel's own surface is
        // the plane. Panels differ in size, which identifies the surface
        // without a per-frame property round-trip.
        if let panel = ActiveDisplays.shared.activePanel(udid: udid, among: panels),
           let match = candidates.first(where: {
               $0.size.width == Double(panel.pixelSize.width) && $0.size.height == Double(panel.pixelSize.height)
           }) {
            return (match.surface, match.descriptor, panel, candidates.map(\.surface))
        }
        guard let index = FramebufferSurfacePick.index(
            binding: binding,
            candidates: candidates.map(\.size)
        ) else { return nil }
        return (candidates[index].surface, candidates[index].descriptor, nil, candidates.map(\.surface))
    }

    private func metadata(for descriptor: NSObject, panel: DisplayPanel?) -> ScreenMetadata {
        let propertiesSelector = NSSelectorFromString("screenProperties")
        let orientationSelector = NSSelectorFromString("uiOrientation")
        guard descriptor.responds(to: propertiesSelector),
              let properties = descriptor.perform(propertiesSelector)?
              .takeUnretainedValue() as? NSObject,
              let rawValue = invokeUInt32Getter(properties, orientationSelector)
        else {
            return ScreenMetadata(uiOrientation: nil)
        }
        return ScreenMetadata(
            uiOrientation: ScreenOrientation(
                simulatorKitRawValue: panel?.canonicalUIOrientation(Int(rawValue))
                    ?? ScreenOrientation.canonicalRaw(Int(rawValue), xcodeMajor: SimulatorKitFramework.hostXcodeMajor)
            )
        )
    }
}

enum ScreenError: Error, Equatable {
    case ioUnavailable
    case noFramebuffer
    case callbackUnavailable
}
