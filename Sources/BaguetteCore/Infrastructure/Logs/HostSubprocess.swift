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

    func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        stdin: Data,
        onBytes: @escaping @Sendable (Data) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws {
        // A caller-supplied environment replaces the parent's rather
        // than merging into it — see the `Subprocess` doc comment.
        try start(
            child: HostProcess.spawn(
                executable: executable, arguments: arguments, stdin: stdin,
                workingDirectory: workingDirectory, environment: environment
            ),
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
        send(SIGTERM)
    }

    func kill() {
        // `terminate()` is a request a child may trap or outlive; SIGKILL
        // is the escalation that guarantees the waitpid watcher — and so
        // `onExit` — fires. The pid stays owned until `didExit` reaps it,
        // so a kill() after terminate() still reaches the child.
        send(SIGKILL)
    }

    private func send(_ signal: Int32) {
        lock.lock()
        let pid = self.pid
        lock.unlock()
        // Signal only — never close `output` here. The reader queue may be
        // blocked in `availableData`, and closing the descriptor under it
        // raises NSFileHandleOperationException instead of delivering EOF.
        // The child's death closes the pipe's write end, which ends the
        // reader naturally; the watcher then closes the handle after
        // `onExit`.
        if let pid {
            Darwin.kill(pid, signal)
        }
    }

    private func didExit(pid: pid_t) {
        lock.lock()
        if self.pid == pid {
            self.pid = nil
        }
        lock.unlock()
    }
}
