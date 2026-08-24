import Testing
import Foundation
@testable import BaguetteCore

/// The refusal paths.
///
/// Every case here is baguette declining to guess: a manifest that isn't
/// JSON, a row with half a frame, a `when` clause nobody recognises. They
/// sit on the far side of a `throw` from the happy paths, and they're
/// exactly the branches a plugin author hits first — so the message each
/// one produces is part of the contract, not an implementation detail.
@Suite("Plugin refusals")
struct PluginEdgeCaseTests {

    // MARK: - capabilities

    @Test func `capabilities sort by name so a printed list is stable`() {
        // `plugin show` and the manifest round-trip both list them; an
        // unstable order would churn every diff.
        let sorted = [PluginCapability.screenshot, .describeUI, .input, .interface].sorted()
        #expect(sorted == [.describeUI, .input, .interface, .screenshot])
        #expect(PluginCapability.describeUI < PluginCapability.input)
        #expect(!(PluginCapability.screenshot < PluginCapability.input))
    }

    // MARK: - grants

    @Test func `a grant knows which plugin it belongs to`() {
        // So a refusal can name the offender rather than saying a bare
        // "forbidden".
        let grants = PluginGrants()
        let token = grants.issue(plugin: "a11y", capabilities: [.describeUI])
        #expect(grants.plugin(for: token) == "a11y")
    }

    @Test func `an unknown token belongs to no plugin`() {
        let grants = PluginGrants()
        #expect(grants.plugin(for: "made-up") == nil)
        let token = grants.issue(plugin: "a11y", capabilities: [])
        grants.revoke(token)
        #expect(grants.plugin(for: token) == nil)
    }

    // MARK: - manifests

    @Test func `a manifest that isn't JSON is refused`() {
        #expect(throws: PluginManifestError.malformedJSON) {
            _ = try PluginManifest.parsing(json: Data("not json at all".utf8))
        }
    }

    @Test func `a manifest that is JSON but not an object is refused`() {
        #expect(throws: PluginManifestError.malformedJSON) {
            _ = try PluginManifest.parsing(json: Data("[1,2,3]".utf8))
        }
    }

    @Test func `an unrecognised when clause is refused, and says what is allowed`() {
        // `when` is a closed set evaluated by the host, not an
        // expression language — so a typo has to fail loudly at
        // validate time rather than silently never showing the panel.
        let error = PluginManifestError.unknownCondition(expression: "simulator.awake")
        #expect(error.description.contains("simulator.awake"))
        #expect(error.description.contains("simulator.booted"))

        var warnings: [PluginManifestWarning] = []
        #expect(throws: PluginManifestError.unknownCondition(expression: "simulator.awake")) {
            _ = try PluginPanel.parsing(
                dict: [
                    "id": "p", "icon": "list", "when": "simulator.awake",
                    "body": ["kind": "list", "source": "go"],
                ],
                declaredCommands: ["go"],
                warnings: &warnings
            )
        }
    }

    // MARK: - results

    @Test func `a command that prints something other than JSON is refused`() {
        // Not folded into an empty result: a panel rendering nothing
        // reads as "all clear", which is the opposite of what happened.
        #expect(throws: PluginResultError.malformedJSON) {
            _ = try PluginResult.parsing(json: Data("Traceback (most recent call last)".utf8))
        }
    }

    @Test func `a command that prints a JSON array rather than an object is refused`() {
        #expect(throws: PluginResultError.malformedJSON) {
            _ = try PluginResult.parsing(json: Data(#"[{"title":"x"}]"#.utf8))
        }
    }

    @Test func `half a frame is refused rather than guessed at`() {
        // Guessing the missing side would paint a box somewhere the
        // plugin never meant, over a live device.
        #expect(throws: PluginResultError.malformedFrame(index: 0)) {
            _ = try ResultRow.parsing(
                dict: ["title": "Button", "frame": ["x": 1, "y": 2, "width": 3]], index: 0
            )
        }
    }

    @Test func `a frame that isn't an object is refused`() {
        #expect(throws: PluginResultError.malformedFrame(index: 1)) {
            _ = try ResultRow.parsing(dict: ["title": "Button", "frame": "24,380"], index: 1)
        }
    }

    @Test func `every refusal names the row it came from`() {
        // The author's first question is "which row?", so the index is
        // part of every message.
        #expect(PluginResultError.malformedFrame(index: 4).description.contains("4"))
        #expect(PluginResultError.rowMissingTitle(index: 2).description.contains("2"))
        #expect(PluginResultError.malformedRun(index: 7).description.contains("7"))
        #expect(PluginResultError.malformedArgs(index: 1).description.contains("1"))
        #expect(PluginResultError.argsWithoutRun(index: 3).description.contains("3"))
    }

    // MARK: - the dispatch ack

    @Test func `a plugin that answered ok acks ok`() {
        // The ack contract `baguette input` and the CLI share.
        let outcome = PluginDispatch.Outcome.ok(PluginResult(ok: true))
        #expect(outcome.ackJSON == #"{"ok":true}"#)
    }

    @Test func `a plugin that reported its own failure acks with that message`() {
        // The plugin ran fine and said no — its words, not baguette's.
        let outcome = PluginDispatch.Outcome.ok(
            PluginResult(ok: false, message: "Metro isn't running")
        )
        #expect(outcome.ackJSON.contains("Metro isn't running"))
        #expect(outcome.ackJSON.contains(#""ok":false"#))
    }

    @Test func `a plugin that answered not-ok with no message still acks something`() {
        let outcome = PluginDispatch.Outcome.ok(PluginResult(ok: false))
        #expect(outcome.ackJSON.contains("plugin reported failure"))
    }

    @Test func `a plugin that never ran acks baguette's own diagnosis`() {
        #expect(
            PluginDispatch.Outcome.unknownCommand(id: "a11y:nope").ackJSON
                .contains("no installed plugin contributes")
        )
        #expect(
            PluginDispatch.Outcome.spawnFailed("no such file").ackJSON
                .contains("plugin failed to start")
        )
    }
}
