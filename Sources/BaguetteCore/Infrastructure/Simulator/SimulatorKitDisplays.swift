import Foundation

/// Production `Displays` — phone and CarPlay planes share one
/// enumerate probe so screen ids stay consistent across resolves.
final class SimulatorKitDisplays: Displays, @unchecked Sendable {
    let phone: any Display
    let carPlay: any Display
    private let udid: String
    private let host: any DeviceHost
    private let hinge: any Hinge
    private let keys: (any DeviceKeys)?
    private let enumerateIO: () throws -> String

    /// `keys` presses a foldable's hardware keys through the guest; a
    /// display with several panels routes buttons there.
    init(udid: String, host: any DeviceHost, hinge: any Hinge, keys: (any DeviceKeys)? = nil) {
        let enumerateIO = { try SimctlIOCapture.enumerate(udid: udid) }
        self.udid = udid
        self.host = host
        self.hinge = hinge
        self.keys = keys
        self.enumerateIO = enumerateIO
        self.phone = SimulatorKitDisplay(
            kind: .phone,
            udid: udid,
            host: host,
            enumerateIO: enumerateIO,
            hinge: hinge,
            keys: keys
        )
        self.carPlay = SimulatorKitDisplay(
            kind: .carPlay,
            udid: udid,
            host: host,
            enumerateIO: enumerateIO,
            hinge: hinge
        )
    }

    func panel(_ panel: IntegratedPanel) -> any Display {
        SimulatorKitDisplay(
            kind: .phone,
            udid: udid,
            host: host,
            enumerateIO: enumerateIO,
            hinge: hinge,
            keys: keys,
            pinnedPanel: panel
        )
    }
}

/// Synchronous `xcrun simctl io <udid> enumerate` capture.
enum SimctlIOCapture {
    static func enumerate(
        udid: String,
        xcrun: URL = URL(fileURLWithPath: "/usr/bin/xcrun")
    ) throws -> String {
        let process = Process()
        process.executableURL = xcrun
        process.arguments = ["simctl", "io", udid, "enumerate"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ProcessInfo.processInfo.environment
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw SimulatorError.notFound(udid: udid)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
