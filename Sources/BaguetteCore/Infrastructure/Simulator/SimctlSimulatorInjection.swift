import Foundation

/// `SimulatorInjection` backed by `xcrun simctl spawn <udid> launchctl …`.
///
/// Arming is a **read-modify-write**, because `DYLD_INSERT_LIBRARIES` is a
/// single string shared by every injecting feature:
///
/// ```
/// launchctl getenv DYLD_INSERT_LIBRARIES        → what's armed now
///   → InjectedDylibs.adding / .removing         → merge by dylib filename
/// launchctl setenv DYLD_INSERT_LIBRARIES <join> → write it back
/// launchctl unsetenv DYLD_INSERT_LIBRARIES      → or drop it entirely
/// ```
///
/// Writing a bare path instead would mean the second feature to arm
/// silently disarms the first. Dropping the variable on any teardown would
/// mean whichever feature stops first disarms the other.
///
/// All of it is scoped to the simulator's launchd domain, so the value
/// survives until the simulator reboots. Re-arming on boot is the caller's
/// responsibility.
///
/// The orchestration here is pure — argv assembly, stdout collection, the
/// `Subprocess` exit handshake, and the merge — so this file is
/// unit-covered end-to-end via `MockSubprocess`. The `HostProcess`
/// (posix_spawn) plumbing lives in `HostSubprocess`.
final class SimctlSimulatorInjection: SimulatorInjection, @unchecked Sendable {
    private let subprocess: any Subprocess
    private let xcrun: URL

    private static let variable = "DYLD_INSERT_LIBRARIES"

    init(
        subprocess: any Subprocess = HostSubprocess(),
        xcrun: URL = URL(fileURLWithPath: "/usr/bin/xcrun")
    ) {
        self.subprocess = subprocess
        self.xcrun = xcrun
    }

    func arm(dylibPath: String, on simulator: any Simulator) async throws {
        try await locked(simulator) {
            let armed = await self.currentDylibs(on: simulator)
            try await self.write(armed.adding(dylibPath), on: simulator)
        }
    }

    func disarm(dylibPath: String, on simulator: any Simulator) async throws {
        try await locked(simulator) {
            let armed = await self.currentDylibs(on: simulator)
            try await self.write(armed.removing(dylibPath), on: simulator)
        }
    }

    /// Runs `body` holding an exclusive lock on this simulator's environment.
    ///
    /// The read-modify-write is not atomic on its own: if the camera and
    /// motion arm at the same moment, both can read the same old value and
    /// the second `setenv` drops the first one's dylib. The lock is a **file**
    /// lock rather than something on this instance, because `CoreSimulator`
    /// hands out a fresh `SimctlSimulatorInjection` per call and the CLI is a
    /// different process from the server entirely — an in-process lock would
    /// protect nothing.
    private func locked<T>(_ simulator: any Simulator,
                           _ body: () async throws -> T) async throws -> T {
        let fm = FileManager.default
        let directory = URL(fileURLWithPath: InjectedDylibInstaller.defaultSupportDir)
            .appendingPathComponent("locks")
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockPath = directory.appendingPathComponent("\(simulator.udid).inject.lock").path
        let descriptor = open(lockPath, O_CREAT | O_RDWR, 0o644)
        // Running unlocked would silently reintroduce exactly the race this
        // guards, so a lock we cannot take fails the operation instead. That
        // costs nothing in practice: the same support directory holds the
        // installed dylibs, so if it isn't writable there was nothing to arm.
        guard descriptor >= 0 else {
            throw SimulatorInjectionError.lockUnavailable(path: lockPath)
        }
        defer { close(descriptor) }
        // Retry a signal-interrupted wait; anything else is a real failure.
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else {
                throw SimulatorInjectionError.lockUnavailable(path: lockPath)
            }
        }
        defer { flock(descriptor, LOCK_UN) }
        return try await body()
    }

    /// Matches by **file name**, not by whole path. Every release installs
    /// under a fresh sha-keyed directory, so the path this build would arm
    /// is almost never the path an earlier one did; comparing paths would
    /// report "not armed" for a dylib that is very much loaded. Same rule
    /// `InjectedDylibs` merges by.
    func armed(dylibPath: String, on simulator: any Simulator) async -> Bool {
        let name = (dylibPath as NSString).lastPathComponent
        return await currentDylibs(on: simulator).paths
            .contains { ($0 as NSString).lastPathComponent == name }
    }

    /// Reads what's armed right now.
    ///
    /// A failed read is **not** an error: a simulator that never had the
    /// variable set is the normal case on a fresh boot, and failing the arm
    /// over it would make injection unusable. Either way the answer is
    /// "nothing armed".
    private func currentDylibs(on simulator: any Simulator) async -> InjectedDylibs {
        let read = try? await spawn(arguments: [
            "simctl", "spawn", simulator.udid,
            "launchctl", "getenv", Self.variable,
        ])
        return InjectedDylibs.parsing(read)
    }

    private func write(_ dylibs: InjectedDylibs, on simulator: any Simulator) async throws {
        // An empty value is not the same as no value — dyld reports an
        // empty entry as a library it failed to load — so the last dylib
        // leaving takes the whole variable with it.
        let arguments = dylibs.isEmpty
            ? ["launchctl", "unsetenv", Self.variable]
            : ["launchctl", "setenv", Self.variable, dylibs.environmentValue]
        _ = try await spawn(arguments: ["simctl", "spawn", simulator.udid] + arguments)
    }

    /// Runs one `xcrun` invocation, returning whatever it wrote to stdout.
    @discardableResult
    private func spawn(arguments: [String]) async throws -> String {
        final class Output: @unchecked Sendable {
            var data = Data()
        }
        let output = Output()
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try subprocess.run(
                    executable: xcrun,
                    arguments: arguments,
                    onBytes: { output.data.append($0) },
                    onExit: { code in
                        if code == 0 {
                            continuation.resume(
                                returning: String(decoding: output.data, as: UTF8.self))
                        } else {
                            continuation.resume(
                                throwing: SimulatorInjectionError.simctlFailed(status: code))
                        }
                    }
                )
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum SimulatorInjectionError: Error, Equatable, CustomStringConvertible {
    case simctlFailed(status: Int32)
    /// The per-simulator lock guarding `DYLD_INSERT_LIBRARIES` couldn't be
    /// taken. Reported rather than skipped: proceeding unlocked would let a
    /// concurrent arm drop another feature's dylib, invisibly.
    case lockUnavailable(path: String)

    var description: String {
        switch self {
        case .simctlFailed(let status):
            return "xcrun simctl exited \(status) while arming/disarming an injected dylib"
        case .lockUnavailable(let path):
            return "could not lock \(path) to update DYLD_INSERT_LIBRARIES"
        }
    }
}
