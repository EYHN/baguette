import Testing
import Foundation
import Mockable
@testable import BaguetteCore

@Suite("Paste")
struct PasteTests {

    // MARK: - parse

    @Test func `parses text and defaults press to true`() throws {
        let p = try Paste.parse(["type": "paste", "text": "hello"])
        #expect(p.text == "hello")
        #expect(p.press == true)
    }

    @Test func `parses press false`() throws {
        let p = try Paste.parse(["text": "hello", "press": false])
        #expect(p.press == false)
    }

    @Test func `parses non-ASCII text verbatim`() throws {
        let p = try Paste.parse(["text": "héllo 🥖"])
        #expect(p.text == "héllo 🥖")
    }

    @Test func `rejects a missing text field`() {
        #expect(throws: GestureError.missingField("text")) {
            try Paste.parse([:])
        }
    }

    // MARK: - execute

    @Test func `execute sets the pasteboard text then presses command-V`() async throws {
        let pasteboard = MockPasteboard()
        let input = MockInput()
        given(pasteboard).setText(.any).willReturn(())
        given(input).key(.any, modifiers: .any, duration: .any).willReturn(true)

        let ok = try await Paste(text: "hello", press: true)
            .execute(pasteboard: pasteboard, input: input)

        #expect(ok == true)
        verify(pasteboard).setText(.value("hello")).called(1)
        verify(input).key(
            .value(KeyboardKey.from(wireCode: "KeyV")!),
            modifiers: .value([.command]),
            duration: .value(0)
        ).called(1)
    }

    @Test func `execute skips the keystroke when press is false`() async throws {
        let pasteboard = MockPasteboard()
        let input = MockInput()
        given(pasteboard).setText(.any).willReturn(())

        let ok = try await Paste(text: "hello", press: false)
            .execute(pasteboard: pasteboard, input: input)

        #expect(ok == true)
        verify(pasteboard).setText(.value("hello")).called(1)
        verify(input).key(.any, modifiers: .any, duration: .any).called(0)
    }

    @Test func `execute propagates a pasteboard failure without pressing`() async {
        let pasteboard = MockPasteboard()
        let input = MockInput()
        given(pasteboard).setText(.any)
            .willThrow(PasteboardError.simctlFailed(status: 1))

        var caught: PasteboardError?
        do {
            _ = try await Paste(text: "hello", press: true)
                .execute(pasteboard: pasteboard, input: input)
        } catch {
            caught = error as? PasteboardError
        }

        #expect(caught == .simctlFailed(status: 1))
        verify(input).key(.any, modifiers: .any, duration: .any).called(0)
    }

    @Test func `execute reports false when the command-V press fails`() async throws {
        let pasteboard = MockPasteboard()
        let input = MockInput()
        given(pasteboard).setText(.any).willReturn(())
        given(input).key(.any, modifiers: .any, duration: .any).willReturn(false)

        let ok = try await Paste(text: "hello", press: true)
            .execute(pasteboard: pasteboard, input: input)
        #expect(ok == false)
    }
}
