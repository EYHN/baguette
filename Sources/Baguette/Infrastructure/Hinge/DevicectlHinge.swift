import Foundation

/// `Hinge` read through `xcrun devicectl device motion hinge-angle`.
///
/// The monitor streams samples until its own timeout, but the first one
/// carries the current angle and arrives in ~0.3 s, before any motion —
/// so this spawns it, takes that sample, and terminates the child. An
/// exit before a sample (a device with no hinge makes devicectl print
/// an error and quit) or a silent child past `deadline` is "no reading".
///
/// The orchestration — argv, byte-to-line splitting, first-sample
/// detection, terminate, deadline — is unit-covered through
/// `MockSubprocess`; only `HostSubprocess`'s `Process` plumbing is
/// integration-only.
final class DevicectlHinge: Hinge, @unchecked Sendable {
    private let udid: String
    /// A fresh child per call: `angle()` and each `watch` own their
    /// own monitor and terminate only that one.
    private let subprocess: () -> any Subprocess
    private let xcrun: URL
    private let deadline: TimeInterval

    init(
        udid: String,
        subprocess: @escaping () -> any Subprocess = { HostSubprocess() },
        xcrun: URL = URL(fileURLWithPath: "/usr/bin/xcrun"),
        deadline: TimeInterval = 3
    ) {
        self.udid = udid
        self.subprocess = subprocess
        self.xcrun = xcrun
        self.deadline = deadline
    }

    func angle() -> HingeAngle? {
        final class State: @unchecked Sendable {
            let lock = NSLock()
            var buffer = LineBuffer()
            var reading: HingeAngle?
            var settled = false
            let done = DispatchSemaphore(value: 0)

            func settle(_ angle: HingeAngle?) {
                lock.lock()
                defer { lock.unlock() }
                guard !settled else { return }
                settled = true
                reading = angle
                done.signal()
            }
        }
        let state = State()
        let child = subprocess()
        do {
            try child.run(
                executable: xcrun,
                arguments: Self.arguments(udid: udid, timeout: 5, everyChange: false),
                onBytes: { bytes in
                    state.lock.lock()
                    let lines = state.buffer.append(bytes)
                    state.lock.unlock()
                    for line in lines {
                        if let angle = HingeAngle.parse(devicectlLine: line) {
                            state.settle(angle)
                            return
                        }
                    }
                },
                onExit: { _ in state.settle(nil) }
            )
        } catch {
            return nil
        }
        _ = state.done.wait(timeout: .now() + deadline)
        state.settle(nil)
        child.terminate()
        return state.reading
    }

    /// devicectl only reads; `SharedHinge` drives through its motor.
    func fold(to degrees: Double, over duration: TimeInterval) throws {
        throw HingeError.toolMissing
    }

    func watch(onAngle: @escaping @Sendable (HingeAngle) -> Void) -> any HingeWatch {
        let watch = Watch(child: subprocess())
        do {
            try watch.child.run(
                executable: xcrun,
                arguments: Self.arguments(udid: udid, timeout: 86_400, everyChange: true),
                onBytes: { bytes in
                    for line in watch.lines(from: bytes) {
                        if let angle = HingeAngle.parse(devicectlLine: line) {
                            onAngle(angle)
                        }
                    }
                },
                onExit: { _ in watch.cancel() }
            )
        } catch {
            watch.cancel()
        }
        return watch
    }

    /// `everyChange` asks for the 60 Hz sweep Device Hub produces
    /// rather than the monitor's default 1° / 1 s cadence. devicectl
    /// refuses a `--timeout` under 5.
    private static func arguments(udid: String, timeout: Int, everyChange: Bool) -> [String] {
        var args = [
            "devicectl", "device", "motion", "hinge-angle",
            "--device", udid,
            "--timeout", "\(timeout)",
        ]
        if everyChange {
            args += ["--update-interval", "0.01", "--change-threshold", "0.1"]
        }
        return args
    }

    private final class Watch: HingeWatch, @unchecked Sendable {
        let child: any Subprocess
        private let lock = NSLock()
        private var buffer = LineBuffer()
        private var cancelled = false

        init(child: any Subprocess) { self.child = child }

        /// Lines completed by `bytes`, or none once cancelled — a
        /// sample the pipe still held must not reach a caller that has
        /// moved on.
        func lines(from bytes: Data) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            guard !cancelled else { return [] }
            return buffer.append(bytes)
        }

        func cancel() {
            lock.lock()
            let first = !cancelled
            cancelled = true
            lock.unlock()
            if first { child.terminate() }
        }
    }
}
