import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// `CopyDispatch` intercepts `copy` wire lines ahead of the gesture
/// registry on both entry points (`baguette input` stdin, serve WS) —
/// the mirror of `PasteDispatch`. Where paste rides text *into* the
/// sim, copy presses Cmd+C so the focused field copies its selection,
/// then ferries the sim's pasteboard *out* onto the host Mac
/// (`simctl pbsync <udid> host`), so it needs the async `Pasteboard`
/// AND the `Input` keystroke path. Anything that isn't a copy line
/// falls through untouched so `GestureDispatcher` keeps owning
/// gestures and error acks.
@Suite("CopyDispatch")
struct CopyDispatchTests {

    private func surfaces() -> (MockPasteboard, MockInput) {
        let pasteboard = MockPasteboard()
        let input = MockInput()
        given(pasteboard).syncToHost().willReturn(())
        given(input).key(.any, modifiers: .any, duration: .any).willReturn(true)
        return (pasteboard, input)
    }

    // MARK: - routing

    @Test func `a non-copy line falls through as notCopy`() async {
        let (pasteboard, input) = surfaces()
        for line in [
            #"{"type":"tap","x":1,"y":2,"width":390,"height":844}"#,
            #"{"type":"paste","text":"hi"}"#,
            "not json at all",
            #"{"no_type":true}"#,
        ] {
            let outcome = await CopyDispatch.dispatch(
                line: line, pasteboard: pasteboard, input: input
            )
            #expect(outcome == .notCopy)
        }
        verify(pasteboard).syncToHost().called(0)
    }

    @Test func `a valid copy line presses Cmd+C, syncs to the host, and acks ok`() async {
        let (pasteboard, input) = surfaces()
        let outcome = await CopyDispatch.dispatch(
            line: #"{"type":"copy"}"#, pasteboard: pasteboard, input: input
        )
        #expect(outcome == .ok)
        verify(input).key(.any, modifiers: .value([.command]), duration: .any).called(1)
        verify(pasteboard).syncToHost().called(1)
    }

    @Test func `press false ferries without a keystroke`() async {
        let (pasteboard, input) = surfaces()
        let outcome = await CopyDispatch.dispatch(
            line: #"{"type":"copy","press":false}"#, pasteboard: pasteboard, input: input
        )
        #expect(outcome == .ok)
        verify(input).key(.any, modifiers: .any, duration: .any).called(0)
        verify(pasteboard).syncToHost().called(1)
    }

    @Test func `dispatches with surfaces vended by the simulator`() async {
        let sim = MockSimulator()
        let (pasteboard, input) = surfaces()
        given(sim).pasteboard().willReturn(pasteboard)
        given(sim).input().willReturn(input)

        let outcome = await CopyDispatch.dispatch(
            line: #"{"type":"copy"}"#, pasteboard: sim.pasteboard(), input: sim.input()
        )
        #expect(outcome == .ok)
    }

    @Test func `a simctl failure surfaces in the outcome`() async {
        let input = MockInput()
        given(input).key(.any, modifiers: .any, duration: .any).willReturn(true)
        let pasteboard = MockPasteboard()
        given(pasteboard).syncToHost()
            .willThrow(PasteboardError.simctlFailed(status: 1))

        let outcome = await CopyDispatch.dispatch(
            line: #"{"type":"copy","press":false}"#, pasteboard: pasteboard, input: input
        )
        #expect(outcome == .failed("xcrun simctl pasteboard command exited 1"))
    }

    // MARK: - projections

    @Test func `outcomes project to stdin acks and typed copy_result frames`() {
        #expect(CopyDispatch.Outcome.notCopy.ackJSON == nil)
        #expect(CopyDispatch.Outcome.notCopy.resultFrame == nil)

        #expect(CopyDispatch.Outcome.ok.ackJSON == #"{"ok":true}"#)
        #expect(CopyDispatch.Outcome.ok.resultFrame
            == #"{"type":"copy_result","ok":true}"#)

        let failed = CopyDispatch.Outcome.failed("bad \"quote\"")
        #expect(failed.ackJSON == #"{"ok":false,"error":"bad \"quote\""}"#)
        #expect(failed.resultFrame
            == #"{"type":"copy_result","ok":false,"error":"bad \"quote\""}"#)
    }
}
