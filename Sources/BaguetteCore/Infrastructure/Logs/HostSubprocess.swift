import Darwin
import Foundation

/// Production `Subprocess` — wraps the small POSIX host-process launcher.
/// The only Infrastructure code in the logs path that touches the real OS
/// spawn pipeline. Integration-only
/// (manually smoke-tested via `baguette logs` against a booted
/// simulator); the orchestrator's behaviour is unit-covered
/// against `MockSubprocess`.
///
/// Single-shot — one `run(...)` call per instance.
final class HostSubprocess: Subprocess, @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t?
    private var output: FileHandle?

    init() {}

    deinit {
        terminate()
    }

    func run(
        executable: URL,
        arguments: [String],
        onBytes: @escaping @Sendable (Data) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws {
        // No stdin payload: the child gets /dev/null, detaching it from any
        // controlling terminal so a SIGINT handed to the parent (Ctrl-C in
        // `baguette logs`) doesn't also kill the child via the foreground
        // pgid before the parent's own SIGTERM handler runs.
        try start(
            child: HostProcess.spawn(executable: executable, arguments: arguments, stdin: nil),
            onBytes: onBytes, onExit: onExit
        )
    }

    func run(
        executable: URL,
        arguments: [String],
        stdin: Data,
        onBytes: @escaping @Sendable (Data) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws {
        // A pipe has no controlling tty, so the SIGINT detachment
        // concern of the no-stdin variant doesn't apply here.
        try start(
            child: HostProcess.spawn(executable: executable, arguments: arguments, stdin: stdin),
            onBytes: onBytes, onExit: onExit
        )
    }

    private func start(
        child: HostProcess.Child,
        onBytes: @escaping @Sendable (Data) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) {
        lock.lock()
        pid = child.pid
        output = child.output
        lock.unlock()

        let readerQueue = DispatchQueue(label: "baguette.host-subprocess.\(child.pid)")
        readerQueue.async {
            while true {
                let bytes = child.output.availableData
                guard !bytes.isEmpty else { break }
                onBytes(bytes)
            }
        }
        DispatchQueue.global().async { [self] in
            let status = HostProcess.wait(for: child.pid)
            didExit(pid: child.pid)
            readerQueue.async {
                try? child.output.close()
                onExit(status)
            }
        }
    }

    func terminate() {
        lock.lock()
        let pid = self.pid
        self.pid = nil
        let output = self.output
        self.output = nil
        lock.unlock()
        if let pid {
            kill(pid, SIGTERM)
        }
        try? output?.close()
    }

    private func didExit(pid: pid_t) {
        lock.lock()
        if self.pid == pid {
            self.pid = nil
            output = nil
        }
        lock.unlock()
    }
}
