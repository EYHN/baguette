import Testing
import Foundation
@testable import BaguetteCore

@Suite("Logger")
struct LoggerTests {

    // The function only writes to stderr; we don't intercept the FILE*
    // here — calling it just exercises the body so a future change that
    // crashes (e.g. dereferencing a nil format) gets caught.
    @Test func `log prints without throwing`() {
        log("test message")
        log("")
    }

    // Same deal as `log` — the styling decision is covered in
    // TerminalStyleTests; this just exercises the write path.
    @Test func `warn prints without throwing`() {
        warn("test warning")
        warn("")
    }

    @Test func `a descriptor that isn't a terminal gets no colour`() {
        // -1 is never a tty, so this is deterministic. Asserting on
        // STDERR_FILENO would not be: `swift test` inherits the parent's
        // stderr, which is a terminal when run interactively and a pipe
        // in CI, so the expected value would flip with the environment.
        #expect(terminalColorized(-1) == false)
    }
}
