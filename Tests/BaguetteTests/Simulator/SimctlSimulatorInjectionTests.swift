import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// Orchestration coverage for `SimctlSimulatorInjection` — argv assembly
/// and the `Subprocess` exit handshake for arming a dylib into a
/// simulator's launchd domain.
///
/// Arming is a **read-modify-write**: `launchctl getenv` first, merge via
/// `InjectedDylibs`, then `setenv` (or `unsetenv` when nothing is left).
/// That's what lets the camera and motion dylibs coexist in one
/// `DYLD_INSERT_LIBRARIES` instead of clobbering each other.
///
/// The irreducible `xcrun` spawn lives in `HostSubprocess`
/// (integration-only), so every branch here is driven through
/// `MockSubprocess`.
@Suite("SimctlSimulatorInjection")
struct SimctlSimulatorInjectionTests {

    private let camera = "/builds/abc123/VirtualCamera.dylib"
    private let motion = "/builds/def456/BaguetteMotion.dylib"

    final class Captures: @unchecked Sendable {
        var executable: URL?
        /// Every spawn, in order — arming makes two.
        var spawns: [[String]] = []
        var writes: [[String]] { spawns.filter { $0.contains("setenv") || $0.contains("unsetenv") } }
        var lastWrite: [String]? { writes.last }
    }

    /// - Parameters:
    ///   - armed: what `launchctl getenv` reports is already armed.
    ///   - readExit: exit status for the `getenv` spawn — non-zero models a
    ///     simulator where the variable was never set.
    ///   - writeExit: exit status for the `setenv` / `unsetenv` spawn.
    private func makeInjection(
        armed: String? = nil,
        readExit: Int32 = 0,
        writeExit: Int32 = 0
    ) -> (SimctlSimulatorInjection, MockSimulator, Captures) {
        let sub = MockSubprocess()
        let sim = MockSimulator()
        given(sim).udid.willReturn("U")
        let captures = Captures()
        given(sub).run(
            executable: .any, arguments: .any,
            onBytes: .any, onExit: .any
        ).willProduce { exe, args, onBytes, onExit in
            captures.executable = exe
            captures.spawns.append(args)
            if args.contains("getenv") {
                if let armed { onBytes(Data("\(armed)\n".utf8)) }
                onExit(readExit)
            } else {
                onExit(writeExit)
            }
        }
        given(sub).terminate().willReturn()
        return (SimctlSimulatorInjection(subprocess: sub), sim, captures)
    }

    @Test func `arm reads the current value before writing the merged one`() async throws {
        let (injection, sim, captures) = makeInjection()
        try await injection.arm(dylibPath: camera, on: sim)

        #expect(captures.executable == URL(fileURLWithPath: "/usr/bin/xcrun"))
        #expect(captures.spawns.first == [
            "simctl", "spawn", "U",
            "launchctl", "getenv", "DYLD_INSERT_LIBRARIES",
        ])
        #expect(captures.lastWrite == [
            "simctl", "spawn", "U",
            "launchctl", "setenv", "DYLD_INSERT_LIBRARIES", camera,
        ])
    }

    @Test func `arm keeps a dylib another feature already armed`() async throws {
        // Starting the camera while motion is armed must not disarm motion.
        let (injection, sim, captures) = makeInjection(armed: motion)
        try await injection.arm(dylibPath: camera, on: sim)

        #expect(captures.lastWrite?.last == "\(motion):\(camera)")
    }

    @Test func `disarm rewrites the value when another dylib is still armed`() async throws {
        // Stopping the camera must leave motion loaded, so this is a
        // setenv of the survivor — not an unsetenv.
        let (injection, sim, captures) = makeInjection(armed: "\(motion):\(camera)")
        try await injection.disarm(dylibPath: camera, on: sim)

        #expect(captures.lastWrite == [
            "simctl", "spawn", "U",
            "launchctl", "setenv", "DYLD_INSERT_LIBRARIES", motion,
        ])
    }

    @Test func `disarm unsets the variable once nothing is left`() async throws {
        // An empty value is not the same as no value — dyld treats an empty
        // entry as a path it failed to load, so the variable must go away.
        let (injection, sim, captures) = makeInjection(armed: camera)
        try await injection.disarm(dylibPath: camera, on: sim)

        #expect(captures.lastWrite == [
            "simctl", "spawn", "U",
            "launchctl", "unsetenv", "DYLD_INSERT_LIBRARIES",
        ])
    }

    @Test func `armed reports whether this simulator would load a dylib`() async {
        let (injection, sim, _) = makeInjection(armed: "\(motion):\(camera)")

        #expect(await injection.armed(dylibPath: camera, on: sim))
        #expect(await injection.armed(dylibPath: "/builds/x/VirtualNetwork.dylib", on: sim)
                    == false)
    }

    @Test func `armed matches by file name, not by build path`() async {
        // Every release installs under a fresh sha-keyed directory, so the
        // path this build would arm is almost never the path an earlier one
        // did. Comparing whole paths would report "not armed" for a dylib
        // that is very much loaded — the same reason `InjectedDylibs`
        // merges by file name.
        let (injection, sim, _) = makeInjection(armed: "/builds/OLD/VirtualCamera.dylib")

        #expect(await injection.armed(dylibPath: camera, on: sim))
    }

    @Test func `armed reports nothing armed when the value cannot be read`() async {
        // A fresh boot never had the variable set. That's "nothing armed",
        // not an error to surface.
        let (injection, sim, _) = makeInjection(readExit: 1)

        #expect(await injection.armed(dylibPath: camera, on: sim) == false)
    }

    @Test func `treats an unreadable current value as nothing armed`() async throws {
        // A simulator that never had the variable set is the normal case,
        // and `launchctl getenv` is not required to succeed for it. Failing
        // the whole arm over that would make the feature unusable on a
        // fresh boot.
        let (injection, sim, captures) = makeInjection(readExit: 1)
        try await injection.arm(dylibPath: camera, on: sim)

        #expect(captures.lastWrite?.last == camera)
    }

    @Test func `a failed write propagates as an injection failure`() async {
        let (injection, sim, _) = makeInjection(writeExit: 2)

        var threw = false
        do {
            try await injection.arm(dylibPath: camera, on: sim)
        } catch {
            threw = true
            #expect((error as? SimulatorInjectionError) == .simctlFailed(status: 2))
        }
        #expect(threw)
    }
}
