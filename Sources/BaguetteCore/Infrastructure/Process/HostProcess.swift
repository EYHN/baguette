import Darwin
import Foundation

/// Minimal host-process launcher shared by the simulator adapters.
///
/// `Foundation.Process` is unavailable to Mac Catalyst even though a
/// Catalyst app is still running on macOS. The simulator stack only needs a
/// small POSIX subset: spawn a known executable, merge stdout and stderr, and
/// optionally terminate a long-running child. Keeping that plumbing here also
/// avoids making the package pretend to support iPhone or iPad.
enum HostProcess {
    struct Child: @unchecked Sendable {
        let pid: pid_t
        let output: FileHandle
    }

    struct Result: Sendable {
        let output: Data
        let status: Int32
    }

    static func spawn(executable: URL, arguments: [String]) throws -> Child {
        try spawn(executable: executable, arguments: arguments, stdin: nil)
    }

    /// Like `spawn(executable:arguments:)`, but feeds `stdin` to the child's
    /// standard input and closes it (EOF) once written. Without a payload the
    /// child gets `/dev/null` — detached from any controlling terminal, so a
    /// SIGINT handed to the parent doesn't also kill the child via the
    /// foreground pgid before the parent's own handlers run.
    static func spawn(executable: URL, arguments: [String], stdin stdinData: Data?) throws -> Child {
        try spawn(executable: executable, arguments: arguments, stdin: stdinData, workingDirectory: nil, environment: nil)
    }

    /// Like the `stdin` variant, but also pins the child's working directory
    /// and replaces its environment. A non-nil `environment` is the child's
    /// *complete* environment — it is not merged with the parent's (see the
    /// `Subprocess` doc comment).
    static func spawn(
        executable: URL,
        arguments: [String],
        stdin stdinData: Data?,
        workingDirectory: URL?,
        environment: [String: String]?
    ) throws -> Child {
        let pipe = Pipe()
        let readDescriptor = pipe.fileHandleForReading.fileDescriptor
        let writeDescriptor = pipe.fileHandleForWriting.fileDescriptor
        let stdinPipe = stdinData == nil ? nil : Pipe()

        // Close-on-exec on every parent-side end. A concurrent spawn from
        // any thread would otherwise hand copies of these descriptors to an
        // unrelated child; a long-lived one then keeps this pipe's write end
        // open and the reader never sees EOF after our child exits. The
        // child's own stdio is wired through adddup2 below, and dup2 clears
        // the flag on the duplicate.
        for descriptor in [readDescriptor, writeDescriptor,
                           stdinPipe?.fileHandleForReading.fileDescriptor,
                           stdinPipe?.fileHandleForWriting.fileDescriptor] {
            if let descriptor {
                _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
            }
        }

        var actions: posix_spawn_file_actions_t?
        try requireSuccess(posix_spawn_file_actions_init(&actions), operation: "posix_spawn_file_actions_init")
        defer { posix_spawn_file_actions_destroy(&actions) }

        // Reset every signal to its default disposition and clear the mask,
        // as Foundation.Process does. Ignored dispositions survive
        // posix_spawn — a host that ignores SIGTERM (swift test's runner
        // does) would otherwise breed children that `terminate()` cannot
        // stop.
        var attributes: posix_spawnattr_t?
        try requireSuccess(posix_spawnattr_init(&attributes), operation: "posix_spawnattr_init")
        defer { posix_spawnattr_destroy(&attributes) }
        var emptySet = sigset_t()
        sigemptyset(&emptySet)
        try requireSuccess(
            posix_spawnattr_setsigmask(&attributes, &emptySet),
            operation: "posix_spawnattr_setsigmask"
        )
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        try requireSuccess(
            posix_spawnattr_setsigdefault(&attributes, &allSignals),
            operation: "posix_spawnattr_setsigdefault"
        )
        try requireSuccess(
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)),
            operation: "posix_spawnattr_setflags"
        )

        try requireSuccess(
            posix_spawn_file_actions_adddup2(&actions, writeDescriptor, STDOUT_FILENO),
            operation: "posix_spawn_file_actions_adddup2(stdout)"
        )
        try requireSuccess(
            posix_spawn_file_actions_adddup2(&actions, writeDescriptor, STDERR_FILENO),
            operation: "posix_spawn_file_actions_adddup2(stderr)"
        )
        try requireSuccess(
            posix_spawn_file_actions_addclose(&actions, readDescriptor),
            operation: "posix_spawn_file_actions_addclose(read)"
        )
        try requireSuccess(
            posix_spawn_file_actions_addclose(&actions, writeDescriptor),
            operation: "posix_spawn_file_actions_addclose(write)"
        )
        if let stdinPipe {
            try requireSuccess(
                posix_spawn_file_actions_adddup2(&actions, stdinPipe.fileHandleForReading.fileDescriptor, STDIN_FILENO),
                operation: "posix_spawn_file_actions_adddup2(stdin)"
            )
            try requireSuccess(
                posix_spawn_file_actions_addclose(&actions, stdinPipe.fileHandleForWriting.fileDescriptor),
                operation: "posix_spawn_file_actions_addclose(stdin-write)"
            )
        } else {
            try "/dev/null".withCString { path in
                try requireSuccess(
                    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, path, O_RDONLY, 0),
                    operation: "posix_spawn_file_actions_addopen(stdin)"
                )
            }
        }

        if let workingDirectory {
            try workingDirectory.path.withCString { path in
                try requireSuccess(
                    posix_spawn_file_actions_addchdir_np(&actions, path),
                    operation: "posix_spawn_file_actions_addchdir_np"
                )
            }
        }

        let strings = [executable.path] + arguments
        let allocatedArguments = strings.map { strdup($0) }
        defer { allocatedArguments.forEach { free($0) } }
        var argv = allocatedArguments + [nil]
        let allocatedEnvironment = environment.map { $0.map { strdup("\($0.key)=\($0.value)") } }
        defer { allocatedEnvironment?.forEach { free($0) } }
        var pid: pid_t = 0
        let spawnStatus = executable.path.withCString { path in
            argv.withUnsafeMutableBufferPointer { argvBuffer -> Int32 in
                if let allocatedEnvironment {
                    var envp = allocatedEnvironment + [nil]
                    return envp.withUnsafeMutableBufferPointer { envpBuffer in
                        posix_spawn(&pid, path, &actions, &attributes, argvBuffer.baseAddress!, envpBuffer.baseAddress!)
                    }
                }
                return posix_spawn(&pid, path, &actions, &attributes, argvBuffer.baseAddress!, environ)
            }
        }

        guard spawnStatus == 0 else {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
            try? stdinPipe?.fileHandleForReading.close()
            try? stdinPipe?.fileHandleForWriting.close()
            throw posixError(operation: "posix_spawn", code: spawnStatus)
        }

        try? pipe.fileHandleForWriting.close()
        if let stdinPipe, let stdinData {
            try? stdinPipe.fileHandleForReading.close()
            // Feed stdin off the calling thread — a payload past the
            // 64 KB pipe buffer would otherwise block here until the
            // child drains it. Closing the handle delivers EOF.
            DispatchQueue.global(qos: .userInitiated).async {
                let handle = stdinPipe.fileHandleForWriting
                try? handle.write(contentsOf: stdinData)
                try? handle.close()
            }
        }
        return Child(pid: pid, output: pipe.fileHandleForReading)
    }

    static func capture(executable: URL, arguments: [String]) throws -> Result {
        let child = try spawn(executable: executable, arguments: arguments)
        let output = child.output.readDataToEndOfFile()
        try? child.output.close()
        return Result(output: output, status: wait(for: child.pid))
    }

    static func wait(for pid: pid_t) -> Int32 {
        var rawStatus: Int32 = 0
        var result: pid_t
        repeat {
            result = waitpid(pid, &rawStatus, 0)
        } while result == -1 && errno == EINTR

        guard result == pid else {
            return -1
        }
        let signal = rawStatus & 0x7F
        if signal == 0 {
            return (rawStatus >> 8) & 0xFF
        }
        return 128 + signal
    }

    private static func requireSuccess(_ status: Int32, operation: String) throws {
        guard status == 0 else { throw posixError(operation: operation, code: status) }
    }

    private static func posixError(operation: String, code: Int32) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "\(operation) failed: \(String(cString: strerror(code)))"]
        )
    }
}
