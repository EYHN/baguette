import Testing
import Foundation
@testable import BaguetteCore

/// `TerminalStyle` decides how a message appears on the way to stderr.
/// Pure string composition + a pure colour decision, so the `isatty`
/// call and the environment lookup stay at the call site in `Logger`.
@Suite("TerminalStyle")
struct TerminalStyleTests {

    private static let esc = "\u{001B}"

    // MARK: - Rendering

    @Test func `a coloured warning wraps the message in yellow and resets`() {
        let rendered = TerminalStyle.warning("device will be lost", colored: true)
        #expect(rendered.hasPrefix("\(Self.esc)[33m"))
        #expect(rendered.hasSuffix("\(Self.esc)[0m"))
        #expect(rendered.contains("device will be lost"))
    }

    @Test func `a plain warning carries no escape bytes at all`() {
        // Redirected output has to stay clean — a log file full of
        // escape sequences is worse than no colour.
        let rendered = TerminalStyle.warning("device will be lost", colored: false)
        #expect(!rendered.contains(Self.esc))
    }

    @Test func `a warning is marked as one even without colour`() {
        // Colour is the only cue a human gets on a terminal, but a
        // piped log has none — so the marker has to survive.
        let plain = TerminalStyle.warning("device will be lost", colored: false)
        #expect(plain.contains("warning:"))

        let coloured = TerminalStyle.warning("device will be lost", colored: true)
        #expect(coloured.contains("warning:"))
    }

    @Test func `the reset closes a multi-line warning`() {
        // The advisory wraps across lines; leaving the sequence open
        // would tint everything printed after it.
        let rendered = TerminalStyle.warning("first line\nsecond line", colored: true)
        #expect(rendered.hasSuffix("\(Self.esc)[0m"))
        #expect(rendered.contains("second line"))
    }

    // MARK: - Deciding whether to colour

    @Test func `a terminal gets colour`() {
        #expect(TerminalStyle.shouldColorize(isTTY: true, environment: [:]) == true)
    }

    @Test func `redirected output gets no colour`() {
        #expect(TerminalStyle.shouldColorize(isTTY: false, environment: [:]) == false)
    }

    @Test func `NO_COLOR turns colour off on a terminal`() {
        // https://no-color.org — any non-empty value opts out.
        #expect(TerminalStyle.shouldColorize(
            isTTY: true, environment: ["NO_COLOR": "1"]
        ) == false)
    }

    @Test func `an empty NO_COLOR is ignored`() {
        // The convention is explicit that presence alone isn't enough;
        // the value must be non-empty.
        #expect(TerminalStyle.shouldColorize(
            isTTY: true, environment: ["NO_COLOR": ""]
        ) == true)
    }

    @Test func `a dumb terminal gets no colour`() {
        #expect(TerminalStyle.shouldColorize(
            isTTY: true, environment: ["TERM": "dumb"]
        ) == false)
    }

    @Test func `an ordinary TERM keeps colour`() {
        #expect(TerminalStyle.shouldColorize(
            isTTY: true, environment: ["TERM": "xterm-256color"]
        ) == true)
    }
}
