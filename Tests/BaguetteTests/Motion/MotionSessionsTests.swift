import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// Coverage for `MotionSessions` — the per-simulator motion state the
/// server's stateless route handlers reach through.
///
/// The important behaviour is the asymmetry: starting motion **creates** a
/// session, while a location walk only ever asks for one that already
/// exists. That's what keeps motion opt-in — moving the device must never
/// arm a sim-wide `DYLD_INSERT_LIBRARIES` as a side effect.
@Suite("MotionSessions")
@MainActor
struct MotionSessionsTests {

    private func makeSessions() -> (MotionSessions, MockSimulator) {
        let sim = MockSimulator()
        given(sim).udid.willReturn("U")
        let motion = MockMotion()
        given(motion).publish(.any, on: .any).willReturn(())
        given(motion).clear(on: .any).willReturn(())
        return (MotionSessions(makeMotion: { _ in motion }), sim)
    }

    @Test func `has no session until motion is started`() {
        let (sessions, _) = makeSessions()
        #expect(sessions.active(udid: "U") == nil)
    }

    @Test func `starting creates a session that is then reachable`() {
        let (sessions, sim) = makeSessions()
        let created = sessions.session(for: sim)
        #expect(sessions.active(udid: "U") === created)
    }

    @Test func `reuses one session per simulator so the ledger survives`() {
        // A second `motion` POST must not reset the pedometer — the running
        // totals live on the session.
        let (sessions, sim) = makeSessions()
        #expect(sessions.session(for: sim) === sessions.session(for: sim))
    }

    @Test func `keeps separate sessions per simulator`() {
        let (sessions, sim) = makeSessions()
        let other = MockSimulator()
        given(other).udid.willReturn("V")
        #expect(sessions.session(for: sim) !== sessions.session(for: other))
    }

    @Test func `ending drops the session so a walk stops driving it`() {
        let (sessions, sim) = makeSessions()
        _ = sessions.session(for: sim)
        sessions.end(udid: "U")
        #expect(sessions.active(udid: "U") == nil)
    }
}
