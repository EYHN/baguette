import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// `PasteDispatch` intercepts `paste` wire lines ahead of the gesture
/// registry on both entry points (`baguette input` stdin, serve WS) —
/// the same shape `describe_ui` uses. Anything that isn't a paste
/// line falls through untouched so `GestureDispatcher` keeps owning
/// gestures and error acks.
@Suite("PasteDispatch")
struct PasteDispatchTests {

    private func surfaces() -> (MockPasteboard, MockInput) {
        let pasteboard = MockPasteboard()
        let input = MockInput()
        given(pasteboard).setText(.any).willReturn(())
        given(input).key(.any, modifiers: .any, duration: .any).willReturn(true)
        return (pasteboard, input)
    }

    // MARK: - routing

    @Test func `a non-paste line falls through as notPaste`() async {
        let (pasteboard, input) = surfaces()
        for line in [
            #"{"type":"tap","x":1,"y":2,"width":390,"height":844}"#,
            "not json at all",
            #"{"no_type":true}"#,
        ] {
            let outcome = await PasteDispatch.dispatch(
                line: line, pasteboard: pasteboard, input: input
            )
            #expect(outcome == .notPaste)
        }
        verify(pasteboard).setText(.any).called(0)
    }

    @Test func `a valid paste line sets the pasteboard and acks ok`() async {
        let (pasteboard, input) = surfaces()
        let outcome = await PasteDispatch.dispatch(
            line: #"{"type":"paste","text":"hello"}"#,
            pasteboard: pasteboard, input: input
        )
        #expect(outcome == .ok)
        verify(pasteboard).setText(.value("hello")).called(1)
        verify(input).key(.any, modifiers: .value([.command]), duration: .any).called(1)
    }

    @Test func `dispatches with a pasteboard vended by the simulator`() async {
        let sim = MockSimulator()
        let (pasteboard, input) = surfaces()
        given(sim).pasteboard().willReturn(pasteboard)

        let outcome = await PasteDispatch.dispatch(
            line: #"{"type":"paste","text":"hi"}"#,
            pasteboard: sim.pasteboard(), input: input
        )
        #expect(outcome == .ok)
    }

    @Test func `a malformed paste line acks the parse error`() async {
        let (pasteboard, input) = surfaces()
        let outcome = await PasteDispatch.dispatch(
            line: #"{"type":"paste"}"#,
            pasteboard: pasteboard, input: input
        )
        #expect(outcome == .failed("missing field: text"))
        verify(pasteboard).setText(.any).called(0)
    }

    @Test func `a simctl failure surfaces in the outcome`() async {
        let pasteboard = MockPasteboard()
        let input = MockInput()
        given(pasteboard).setText(.any)
            .willThrow(PasteboardError.simctlFailed(status: 1))

        let outcome = await PasteDispatch.dispatch(
            line: #"{"type":"paste","text":"hello"}"#,
            pasteboard: pasteboard, input: input
        )
        #expect(outcome == .failed("xcrun simctl pasteboard command exited 1"))
    }

    @Test func `a failed command-V press surfaces in the outcome`() async {
        let pasteboard = MockPasteboard()
        let input = MockInput()
        given(pasteboard).setText(.any).willReturn(())
        given(input).key(.any, modifiers: .any, duration: .any).willReturn(false)

        let outcome = await PasteDispatch.dispatch(
            line: #"{"type":"paste","text":"hello"}"#,
            pasteboard: pasteboard, input: input
        )
        #expect(outcome == .failed("Cmd+V dispatch failed"))
    }

    // MARK: - projections

    @Test func `outcomes project to stdin acks and typed paste_result frames`() {
        #expect(PasteDispatch.Outcome.notPaste.ackJSON == nil)
        #expect(PasteDispatch.Outcome.notPaste.resultFrame == nil)

        #expect(PasteDispatch.Outcome.ok.ackJSON == #"{"ok":true}"#)
        #expect(PasteDispatch.Outcome.ok.resultFrame
            == #"{"type":"paste_result","ok":true}"#)

        let failed = PasteDispatch.Outcome.failed("bad \"quote\"")
        #expect(failed.ackJSON == #"{"ok":false,"error":"bad \"quote\""}"#)
        #expect(failed.resultFrame
            == #"{"type":"paste_result","ok":false,"error":"bad \"quote\""}"#)
    }
}
