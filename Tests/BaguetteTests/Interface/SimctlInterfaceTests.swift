import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// Orchestration coverage for `SimctlInterface` — argv assembly + the
/// `Subprocess` exit handshake. The irreducible `xcrun` spawn lives in
/// `HostSubprocess` (integration-only), so every branch here is driven
/// through `MockSubprocess`.
@Suite("SimctlInterface")
struct SimctlInterfaceTests {

    final class Captures: @unchecked Sendable {
        var executable: URL?
        var arguments: [String]?
        var ran = false
    }

    private func makeInterface(
        stdout: String = "", exitCode: Int32 = 0
    ) -> (SimctlInterface, Captures) {
        let sub = MockSubprocess()
        let captures = Captures()
        given(sub).run(
            executable: .any, arguments: .any, onBytes: .any, onExit: .any
        ).willProduce { exe, args, onBytes, onExit in
            captures.ran = true
            captures.executable = exe
            captures.arguments = args
            if !stdout.isEmpty { onBytes(Data(stdout.utf8)) }
            onExit(exitCode)
        }
        given(sub).terminate().willReturn()
        return (SimctlInterface(udid: "U", subprocess: sub), captures)
    }

    // MARK: - reading

    @Test func `reading appearance runs simctl ui appearance with no value`() async throws {
        let (interface, captures) = makeInterface(stdout: "dark\n")
        let appearance = try await interface.appearance()

        #expect(captures.executable == URL(fileURLWithPath: "/usr/bin/xcrun"))
        #expect(captures.arguments == ["simctl", "ui", "U", "appearance"])
        #expect(appearance == .dark)
    }

    @Test func `reading contrast parses simctl's answer`() async throws {
        let (interface, captures) = makeInterface(stdout: "enabled\n")
        #expect(try await interface.increaseContrast() == .enabled)
        #expect(captures.arguments == ["simctl", "ui", "U", "increase_contrast"])
    }

    @Test func `reading content size parses simctl's answer`() async throws {
        let (interface, captures) = makeInterface(stdout: "accessibility-large\n")
        #expect(try await interface.contentSize() == .accessibilityLarge)
        #expect(captures.arguments == ["simctl", "ui", "U", "content_size"])
    }

    @Test func `a shut-down device reads as unknown rather than throwing`() async throws {
        // simctl answers "unknown" and exits 0 for a device that isn't
        // booted. That's a state to show, not an error to raise.
        let (interface, _) = makeInterface(stdout: "unknown\n")
        #expect(try await interface.appearance() == .unknown)
        #expect(try await interface.contentSize() == .unknown)
    }

    // MARK: - writing

    @Test func `setting appearance appends the value to the same verb`() async throws {
        let (interface, captures) = makeInterface()
        try await interface.setAppearance(.dark)
        #expect(captures.arguments == ["simctl", "ui", "U", "appearance", "dark"])
    }

    @Test func `setting contrast appends the value`() async throws {
        let (interface, captures) = makeInterface()
        try await interface.setIncreaseContrast(.enabled)
        #expect(captures.arguments == ["simctl", "ui", "U", "increase_contrast", "enabled"])
    }

    @Test func `setting a content size names the category`() async throws {
        let (interface, captures) = makeInterface()
        try await interface.setContentSize(.size(.accessibilityExtraLarge))
        #expect(captures.arguments == [
            "simctl", "ui", "U", "content_size", "accessibility-extra-large",
        ])
    }

    @Test func `stepping content size passes the relative word through`() async throws {
        let (interface, captures) = makeInterface()
        try await interface.setContentSize(.increment)
        #expect(captures.arguments == ["simctl", "ui", "U", "content_size", "increment"])
    }

    // MARK: - refusals and failures

    @Test func `setting a read-only state is refused before anything is spawned`() async throws {
        // `unknown` is an answer, never an instruction. Catching it here
        // means the error names the real mistake instead of echoing a
        // simctl usage dump.
        let (interface, captures) = makeInterface()
        await #expect(throws: InterfaceError.notSettable("unknown")) {
            try await interface.setAppearance(.unknown)
        }
        #expect(captures.ran == false)
    }

    @Test func `an unsupported contrast is refused the same way`() async throws {
        let (interface, captures) = makeInterface()
        await #expect(throws: InterfaceError.notSettable("unsupported")) {
            try await interface.setIncreaseContrast(.unsupported)
        }
        #expect(captures.ran == false)
    }

    @Test func `a read-only content size is refused rather than applied as large`() async throws {
        // The third setter used to fall back to "large" for a state
        // that can only be read, quietly changing the device to a
        // category nobody asked for.
        let (interface, captures) = makeInterface()
        await #expect(throws: InterfaceError.notSettable("unknown")) {
            try await interface.setContentSize(.size(.unknown))
        }
        #expect(captures.ran == false)
    }

    @Test func `a non-zero exit is reported with its status`() async throws {
        let (interface, _) = makeInterface(exitCode: 3)
        await #expect(throws: InterfaceError.simctlFailed(status: 3)) {
            try await interface.setAppearance(.dark)
        }
    }

    @Test func `a spawn that never starts surfaces its own error`() async throws {
        // Distinct from a non-zero exit: the process didn't run at all
        // (missing xcrun, fork failure). The caller shouldn't see this
        // as a device that answered.
        struct SpawnRefused: Error {}
        let sub = MockSubprocess()
        given(sub).run(
            executable: .any, arguments: .any, onBytes: .any, onExit: .any
        ).willThrow(SpawnRefused())
        given(sub).terminate().willReturn()
        let interface = SimctlInterface(udid: "U", subprocess: sub)

        await #expect(throws: SpawnRefused.self) { try await interface.appearance() }
        await #expect(throws: SpawnRefused.self) { try await interface.setAppearance(.dark) }
    }

    @Test func `a failed read is reported rather than read as unknown`() async throws {
        // A spawn that failed is a different thing from a device that
        // answered "unknown", and callers should be able to tell them
        // apart.
        let (interface, _) = makeInterface(stdout: "", exitCode: 1)
        await #expect(throws: InterfaceError.simctlFailed(status: 1)) {
            try await interface.appearance()
        }
    }
}
