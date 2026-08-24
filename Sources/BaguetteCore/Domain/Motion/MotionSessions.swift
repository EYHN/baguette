import Foundation

/// The motion state of every simulator the server is driving, keyed by udid.
///
/// The server's route handlers are stateless statics, but motion is not: the
/// pedometer's running totals live on a `MotionSession`, and they have to
/// survive from one request to the next. This is where they live.
///
/// The asymmetry between the two lookups is the whole point:
///
/// - `session(for:)` **creates** on first use — what `POST …/motion` does.
/// - `active(udid:)` never creates — what a location walk does.
///
/// So moving the device drives motion when motion is already on, and does
/// nothing at all when it isn't. Arming rewrites a simulator-wide
/// `DYLD_INSERT_LIBRARIES` that only takes effect on the next app launch, so
/// it must never happen as a side effect of a joystick nudge.
@MainActor
final class MotionSessions {

    private var sessions: [String: MotionSession] = [:]
    /// `nonisolated` because it is immutable and touches no isolated
    /// state — that is what lets `init` be nonisolated too.
    private nonisolated let makeMotion: @Sendable (any Simulator) -> any Motion

    /// `nonisolated` so a `Server` — which is not main-actor isolated —
    /// can take one as a default argument. Only stored-property setup
    /// happens here; every read and write afterwards is on the main actor.
    nonisolated init(
        makeMotion: @escaping @Sendable (any Simulator) -> any Motion = { $0.motion() }
    ) {
        self.makeMotion = makeMotion
    }

    /// The session for `simulator`, created on first use. Reused thereafter
    /// so the ledger survives — a second `motion` request must not reset the
    /// pedometer.
    func session(for simulator: any Simulator) -> MotionSession {
        if let existing = sessions[simulator.udid] { return existing }
        let session = MotionSession(motion: makeMotion(simulator))
        sessions[simulator.udid] = session
        return session
    }

    /// The running session, or `nil` when motion was never started on this
    /// simulator. Deliberately does not create one.
    func active(udid: String) -> MotionSession? {
        sessions[udid]
    }

    /// Forget this simulator's session, so a location walk stops driving it.
    func end(udid: String) {
        sessions[udid] = nil
    }
}
