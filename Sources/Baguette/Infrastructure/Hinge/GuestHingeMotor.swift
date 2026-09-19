import Foundation

/// `HingeMotor` that keeps `HingeControl serve` running inside the guest
/// (`xcrun simctl spawn <udid> <HingeControl> serve`) and writes each
/// sweep to it: `sweep <from> <to> <ms>`, `orientation <name>`.
///
/// The tool registers a HID service shaped like dtuhidd's `avpCustom`
/// and dispatches the pose events Device Hub sends (see
/// `Injected/HingeControl/Sources/HingeControl.m`); the runtime folds,
/// SpringBoard swaps panels, and `DevicectlHinge` reads the sweep back
/// like any other. Kept rather than spawned per sweep: a spawn is most
/// of a second, and the service stays registered between poses. Sweeps
/// are played one at a time — a pick during a sweep queues behind it —
/// and the call returns once the sweep has had its time.
///
/// The orchestration — tool lookup, argv, the write, restart after
/// exit — is unit-covered through `MockSubprocess`; `HostSubprocess`
/// is integration-only.
final class GuestHingeMotor: HingeMotor, @unchecked Sendable {
    private let udid: String
    private let subprocess: () -> any Subprocess
    private let tool: () -> String?
    private let xcrun: URL
    private let settle: (TimeInterval) -> Void
    private let lock = NSLock()
    private var child: (any Subprocess)?
    private var generation = 0

    /// `settle` waits for a sweep to play out (sleeps, in production).
    init(
        udid: String,
        subprocess: @escaping () -> any Subprocess = { HostSubprocess() },
        tool: @escaping () -> String? = { InjectedDylibInstaller.installIfNeeded(.hingeControl) },
        xcrun: URL = URL(fileURLWithPath: "/usr/bin/xcrun"),
        settle: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.udid = udid
        self.subprocess = subprocess
        self.tool = tool
        self.xcrun = xcrun
        self.settle = settle
    }

    func fold(from: Double, to: Double, over duration: TimeInterval) throws {
        try send("sweep \(Self.number(from)) \(Self.number(to)) \(Self.number(duration * 1000))")
        settle(duration + 0.05)
    }

    func turn(to orientation: DeviceOrientation) throws {
        let name: String
        switch orientation {
        case .portrait: name = "portrait"
        case .portraitUpsideDown: name = "portraitUpsideDown"
        case .landscapeLeft: name = "landscapeLeft"
        case .landscapeRight: name = "landscapeRight"
        }
        try send("orientation \(name)")
    }

    /// One command line to the serving child, started if need be.
    private func send(_ line: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let child = try serving()
        try child.write(Data((line + "\n").utf8))
    }

    private func serving() throws -> any Subprocess {
        if let child { return child }
        guard let tool = tool() else { throw HingeError.toolMissing }
        generation += 1
        let mine = generation
        let started = subprocess()
        try started.runInteractive(
            executable: xcrun,
            arguments: ["simctl", "spawn", udid, tool, "serve"],
            onBytes: { _ in },
            onExit: { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                if self.generation == mine { self.child = nil }
                self.lock.unlock()
            }
        )
        child = started
        // The service needs a moment to be seen by the event system
        // before its first event lands.
        settle(0.15)
        return started
    }

    /// Whole numbers print without a fraction, for a line that reads well.
    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
