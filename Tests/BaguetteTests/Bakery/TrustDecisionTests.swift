import Testing
import Foundation
@testable import BaguetteCore

@Suite("TrustDecision")
struct TrustDecisionTests {

    @Test func `an already-trusted bakery needs no further consent`() throws {
        // Trust is per bakery, once — installing more from a source you
        // already accepted is friction-free.
        #expect(TrustDecision.decide(alreadyTrusted: true, accepted: false) == .granted)
    }

    @Test func `an explicit acceptance grants consent`() throws {
        // `--yes`, or the browser's Install click.
        #expect(TrustDecision.decide(alreadyTrusted: false, accepted: true) == .granted)
    }

    @Test func `a new untrusted bakery must be asked`() throws {
        #expect(TrustDecision.decide(alreadyTrusted: false, accepted: false) == .mustAsk)
    }

    @Test func `the prompt names the source and warns what trust means`() throws {
        let prompt = TrustDecision.prompt(source: "acme/tools", commit: "abc1234")
        #expect(prompt.contains("acme/tools"))
        #expect(prompt.contains("abc1234"))
        // The warning is the whole point: plugins run as real programs.
        #expect(prompt.lowercased().contains("run"))
    }
}
