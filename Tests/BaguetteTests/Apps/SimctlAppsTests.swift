import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// Orchestration coverage for `SimctlApps` — argv assembly + the
/// `Subprocess` exit handshake. The irreducible `xcrun` spawn lives in
/// `HostSubprocess` (integration-only), so every branch is driven
/// through `MockSubprocess`.
@Suite("SimctlApps")
struct SimctlAppsTests {

    final class Captures: @unchecked Sendable {
        var executable: URL?
        var arguments: [String]?
        var ran = false
    }

    private func makeApps(exitCode: Int32 = 0) -> (SimctlApps, Captures) {
        let sub = MockSubprocess()
        let captures = Captures()
        given(sub).run(
            executable: .any, arguments: .any, onBytes: .any, onExit: .any
        ).willProduce { exe, args, _, onExit in
            captures.ran = true
            captures.executable = exe
            captures.arguments = args
            onExit(exitCode)
        }
        given(sub).terminate().willReturn()
        return (SimctlApps(udid: "U", subprocess: sub), captures)
    }

    @Test func `install spawns xcrun simctl install with the app path`() async throws {
        let (apps, captures) = makeApps()
        try await apps.install(AppBundle(path: URL(fileURLWithPath: "/tmp/MyApp.ipa")))

        #expect(captures.executable == URL(fileURLWithPath: "/usr/bin/xcrun"))
        #expect(captures.arguments == ["simctl", "install", "U", "/tmp/MyApp.ipa"])
    }

    @Test func `a non-zero simctl exit propagates as an install failure`() async {
        let (apps, _) = makeApps(exitCode: 3)
        var caught: AppsError?
        do {
            try await apps.install(AppBundle(path: URL(fileURLWithPath: "/tmp/MyApp.ipa")))
        } catch {
            caught = error as? AppsError
        }
        #expect(caught == .installFailed(status: 3))
    }
}
