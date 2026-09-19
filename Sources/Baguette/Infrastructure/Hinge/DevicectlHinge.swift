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
    private let subprocess: any Subprocess
    private let xcrun: URL
    private let deadline: TimeInterval

    init(
        udid: String,
        subprocess: any Subprocess = HostSubprocess(),
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
        do {
            try subprocess.run(
                executable: xcrun,
                arguments: [
                    "devicectl", "device", "motion", "hinge-angle",
                    "--device", udid,
                    // devicectl refuses anything under 5; the child is
                    // terminated long before that.
                    "--timeout", "5",
                ],
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
        subprocess.terminate()
        return state.reading
    }
}
