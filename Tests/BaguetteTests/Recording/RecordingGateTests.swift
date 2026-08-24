import Testing
import Foundation
@testable import BaguetteCore

/// `baguette record` ends a take for one of two reasons — the user
/// pressed Ctrl-C, or `--duration` ran out — and they arrive on two
/// different `DispatchSource`s that can both fire. `RecordingGate` is
/// the latch that lets exactly one of them through and remembers which,
/// because the answer decides what happens to SIGINT next: after a
/// Ctrl-C the user gets the signal handed back (a second press aborts a
/// long flush), and on the duration path they don't, so that their
/// *first* press can't truncate the file being written.
@Suite("RecordingGate")
struct RecordingGateTests {

    @Test func `a gate opened by the interrupt says so`() async {
        let gate = RecordingGate()
        gate.open(.interrupt)
        await gate.wait()

        #expect(gate.openedBy == .interrupt)
    }

    @Test func `a gate opened by the duration timer says so`() async {
        let gate = RecordingGate()
        gate.open(.duration)
        await gate.wait()

        #expect(gate.openedBy == .duration)
    }

    @Test func `a gate nobody has opened has no reason yet`() {
        #expect(RecordingGate().openedBy == nil)
    }

    @Test func `only the first of the two reasons through counts`() async {
        // Both sources really can fire: the duration deadline and a
        // Ctrl-C a millisecond later. The take ended for the first one.
        let gate = RecordingGate()
        gate.open(.duration)
        gate.open(.interrupt)
        await gate.wait()

        #expect(gate.openedBy == .duration)
    }

    @Test func `a waiter is released by an open that lands after it started waiting`() async {
        let gate = RecordingGate()
        Task.detached {
            gate.open(.interrupt)
        }
        await gate.wait()

        #expect(gate.openedBy == .interrupt)
    }
}
