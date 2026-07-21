import Foundation

/// Production `ExternalDisplays` — clicks the host panel only when
/// CarPlay/TVOut is absent. A Connected Screens hit is enough to skip;
/// black-framebuffer recovery is a separate panel cycle (Disabled →
/// CarPlay) invoked explicitly when capture detects a wedge.
final class HostExternalDisplays: ExternalDisplays, @unchecked Sendable {
    private let panel: any ExternalDisplayPanel
    private let enumerateIO: () throws -> String
    private let lock = NSLock()
    private var enabledAfterSuccess = false

    init(
        panel: any ExternalDisplayPanel = SimulatorMenuExternalDisplayPanel(),
        enumerateIO: @escaping () throws -> String
    ) {
        self.panel = panel
        self.enumerateIO = enumerateIO
    }

    convenience init(udid: String) {
        self.init(enumerateIO: { try SimctlIOCapture.enumerate(udid: udid) })
    }

    var isCarPlayConnected: Bool {
        if let text = try? enumerateIO(),
           SimctlIOEnumerate.isCarPlayConnected(text) {
            return true
        }
        lock.lock()
        defer { lock.unlock() }
        return enabledAfterSuccess
    }

    func enableCarPlay() throws {
        if isCarPlayConnected { return }
        try panel.enableCarPlay()
        lock.lock()
        enabledAfterSuccess = true
        lock.unlock()
    }
}
