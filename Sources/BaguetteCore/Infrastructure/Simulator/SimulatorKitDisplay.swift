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

    func input() -> any Input {
        let binding = (try? resolve()) ?? cachedBinding()
        let screenId = binding?.connectedScreenId ?? 0
        let target = DisplayTouchTarget.resolve(
            kind: kind,
            connectedScreenId: screenId,
            derive: IndigoHIDTargetForScreen.target(for:)
        )
        return IndigoHIDInput(udid: udid, host: host, touchTarget: target)
    }

    private func cachedBinding() -> DisplayBinding? {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }
}
