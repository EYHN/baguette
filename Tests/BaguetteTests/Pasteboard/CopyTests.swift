import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// The `copy` wire verb — the interactive mirror of `Paste`. Where
/// paste sets the pasteboard then presses Cmd+V, copy presses Cmd+C
/// (so the focused field copies its selection into the sim's
/// pasteboard), then ferries that pasteboard onto the host Mac
/// (`syncToHost`). `press:false` skips the keystroke for a pure ferry
/// of whatever the sim already holds.
@Suite("Copy")
struct CopyTests {

    private func surfaces() -> (MockPasteboard, MockInput) {
        let pasteboard = MockPasteboard()
        let input = MockInput()
        given(pasteboard).syncToHost().willReturn(())
        given(input).key(.any, modifiers: .any, duration: .any).willReturn(true)
        return (pasteboard, input)
    }

    // MARK: - parse

    @Test func `parses copy with press defaulting to true`() {
        #expect(Copy.parse(["type": "copy"]) == Copy(press: true))
    }

    @Test func `parses an explicit press false`() {
        #expect(Copy.parse(["type": "copy", "press": false]).press == false)
    }

    // MARK: - execute

    @Test func `execute presses Cmd+C then syncs the pasteboard to the host`() async throws {
        let (pasteboard, input) = surfaces()
        let ok = try await Copy(press: true, settleNanos: 0)
            .execute(pasteboard: pasteboard, input: input)
        #expect(ok)
        verify(input).key(.any, modifiers: .value([.command]), duration: .any).called(1)
        verify(pasteboard).syncToHost().called(1)
    }

    @Test func `execute with press false only syncs, no keystroke`() async throws {
        let (pasteboard, input) = surfaces()
        let ok = try await Copy(press: false, settleNanos: 0)
            .execute(pasteboard: pasteboard, input: input)
        #expect(ok)
        verify(input).key(.any, modifiers: .any, duration: .any).called(0)
        verify(pasteboard).syncToHost().called(1)
    }

    @Test func `a failed Cmd+C press still ferries but reports not-ok`() async throws {
        let pasteboard = MockPasteboard()
        let input = MockInput()
        given(pasteboard).syncToHost().willReturn(())
        given(input).key(.any, modifiers: .any, duration: .any).willReturn(false)

        let ok = try await Copy(press: true, settleNanos: 0)
            .execute(pasteboard: pasteboard, input: input)
        #expect(!ok)
        verify(pasteboard).syncToHost().called(1)
    }
}
