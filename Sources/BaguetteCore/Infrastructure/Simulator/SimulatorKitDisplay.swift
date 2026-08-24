import Foundation

/// One display plane backed by SimulatorKit ports + Connected Screens.
final class SimulatorKitDisplay: Display, @unchecked Sendable {
    let kind: DisplayKind
    private let udid: String
    private let host: any DeviceHost
    private let enumerateIO: () throws -> String
    private let lock = NSLock()
    private var cached: DisplayBinding?

    init(
        kind: DisplayKind,
        udid: String,
        host: any DeviceHost,
        enumerateIO: @escaping () throws -> String
    ) {
        self.kind = kind
        self.udid = udid
        self.host = host
        self.enumerateIO = enumerateIO
    }

    func resolve() throws -> DisplayBinding {
        let sized = try SimulatorKitFramebufferPorts.sizedPorts(udid: udid, host: host)
        let screens = SimctlIOEnumerate.connectedScreens(from: try enumerateIO())
        let ports = FramebufferPortSnapshots.assigningScreenIds(
            ports: sized,
            screens: screens
        )
        let binding = try ConnectedScreens.binding(kind: kind, ports: ports)
        lock.lock()
        cached = binding
        lock.unlock()
        return binding
    }

    func screen() -> any Screen {
        // Prefer a fresh resolve; fall back to the last successful
        // binding so a transient probe miss after bind() doesn't open
        // an unbound phone stream under a CarPlay label.
        let binding = (try? resolve()) ?? cachedBinding()
        return SimulatorKitScreen(udid: udid, host: host, binding: binding)
    }

    /// Input for this plane, resolved once.
    ///
    /// There was a version of this that re-derived the target on every
    /// gesture, to stop a session dispatching to a screen that had gone
    /// away. It is gone, and deliberately: a target is a **constant**
    /// naming a registered service (`IndigoHIDTouchTarget`), not
    /// anything derived from a screen, so there is nothing about it that
    /// can go stale. What that version actually bought was a
    /// `simctl io enumerate` subprocess plus a SimulatorKit port walk in
    /// front of every touch — including every move of a drag — which is
    /// exactly as slow as it sounds.
    ///
    /// Dispatching to a display that has since detached is now harmless:
    /// the service is still registered, so the event is delivered
    /// nowhere rather than throwing. Unregistered targets are what kill
    /// the guest, and this cannot produce one.
    func input() -> any Input {
        let target = DisplayTouchTarget.resolve(
            kind: kind,
            connectedScreenId: 0,
            derive: { _ in nil },
            override: DisplayTouchTarget.parseOverride(
                ProcessInfo.processInfo.environment["BAGUETTE_CARPLAY_TARGET"]
            )
        ) ?? IndigoHIDTouchTarget.phone
        return IndigoHIDInput(udid: udid, host: host, touchTarget: target, plane: kind)
    }

    private func cachedBinding() -> DisplayBinding? {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }
}
