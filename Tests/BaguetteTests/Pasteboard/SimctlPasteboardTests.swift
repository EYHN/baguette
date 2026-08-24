import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// Orchestration coverage for `SimctlPasteboard` — argv assembly, the
/// stdin handoff for `pbcopy`, and the `Subprocess` exit handshake.
/// The irreducible `xcrun` spawn lives in `HostSubprocess`
/// (integration-only), so every branch here is driven through
/// `MockSubprocess`.
@Suite("SimctlPasteboard")
struct SimctlPasteboardTests {

    final class Captures: @unchecked Sendable {
        var executable: URL?
        var arguments: [String]?
        var stdin: Data?
    }

    private func makePasteboard(
        exitCode: Int32 = 0, stdout: Data? = nil
    ) -> (SimctlPasteboard, Captures) {
        let sub = MockSubprocess()
        let captures = Captures()
        given(sub).run(
            executable: .any, arguments: .any, stdin: .any, onBytes: .any, onExit: .any
        ).willProduce { exe, args, stdin, _, onExit in
            captures.executable = exe
            captures.arguments = args
            captures.stdin = stdin
            onExit(exitCode)
        }
        given(sub).run(
            executable: .any, arguments: .any, onBytes: .any, onExit: .any
        ).willProduce { exe, args, onBytes, onExit in
            captures.executable = exe
            captures.arguments = args
            if let stdout { onBytes(stdout) }
            onExit(exitCode)
        }
        given(sub).terminate().willReturn()
        return (SimctlPasteboard(udid: "U", subprocess: sub), captures)
    }

    @Test func `setText spawns xcrun simctl pbcopy with the text on stdin`() async throws {
        let (pasteboard, captures) = makePasteboard()
        try await pasteboard.setText("hi")

        #expect(captures.executable == URL(fileURLWithPath: "/usr/bin/xcrun"))
        #expect(captures.arguments == ["simctl", "pbcopy", "U"])
        #expect(captures.stdin == Data("hi".utf8))
    }

    @Test func `setText sends UTF-8 bytes for non-ASCII text`() async throws {
        let (pasteboard, captures) = makePasteboard()
        try await pasteboard.setText("héllo 🥖")
        #expect(captures.stdin == Data("héllo 🥖".utf8))
    }

    @Test func `text runs simctl pbpaste and returns the captured stdout`() async throws {
        let (pasteboard, captures) = makePasteboard(
            stdout: Data("clip contents".utf8)
        )
        let text = try await pasteboard.text()
        #expect(captures.arguments == ["simctl", "pbpaste", "U"])
        #expect(text == "clip contents")
    }

    @Test func `syncFromHost spawns simctl pbsync from host to the device`() async throws {
        let (pasteboard, captures) = makePasteboard()
        try await pasteboard.syncFromHost()
        #expect(captures.arguments == ["simctl", "pbsync", "host", "U"])
        #expect(captures.stdin == nil)
    }

    @Test func `syncToHost spawns simctl pbsync from the device to host`() async throws {
        let (pasteboard, captures) = makePasteboard()
        try await pasteboard.syncToHost()
        #expect(captures.arguments == ["simctl", "pbsync", "U", "host"])
        #expect(captures.stdin == nil)
    }

    @Test func `a non-zero simctl exit propagates as a pasteboard failure`() async {
        let (pasteboard, _) = makePasteboard(exitCode: 3)
        var caught: PasteboardError?
        do {
            try await pasteboard.setText("hi")
        } catch {
            caught = error as? PasteboardError
        }
        #expect(caught == .simctlFailed(status: 3))
    }
}
