import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// A panel that accepts typed input.
///
/// Every panel before this one was a *report*: the host ran a command
/// and drew what came back. A deep-link bar can't work that way — the
/// interesting value is the one nobody has typed yet — so the list body
/// gains an optional `prompt`, and submitting it invokes the panel's own
/// `source` with the typed text as `args`. That's deliberately the same
/// path `rowAction: "run"` already takes, so no plugin code runs in the
/// page and there's no second command endpoint.
///
/// `prompt` is **additive**: a manifest that omits it parses exactly as
/// before, and an older baguette reading a manifest that has it ignores
/// the key and renders the plain list. That's why `apiVersion` stays 1.
@Suite("PanelPrompt")
struct PanelPromptTests {

    private func body(_ json: String, commands: Set<String> = ["open"]) throws -> PanelBody {
        try PanelBody.parsing(
            dict: JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:],
            declaredCommands: commands
        )
    }

    @Test func `a panel can ask for typed input`() throws {
        let parsed = try body("""
        {"kind":"list","source":"open","rowAction":"run",
         "prompt":{"arg":"url","placeholder":"myapp://path","submit":"Open","filter":true}}
        """)
        #expect(parsed == .list(ListBody(
            source: "open",
            rowAction: .run,
            prompt: PanelPrompt(arg: "url", placeholder: "myapp://path", submit: "Open", filter: true)
        )))
    }

    @Test func `a prompt that names no button label offers a plain one`() throws {
        // The label is chrome, not meaning — a manifest shouldn't have
        // to spell it out to get a usable button.
        let parsed = try body(#"{"kind":"list","source":"open","prompt":{"arg":"url"}}"#)
        guard case .list(let list) = parsed else {
            Issue.record("expected a list body"); return
        }
        #expect(list.prompt?.submit == "Run")
        #expect(list.prompt?.placeholder == nil)
        #expect(list.prompt?.filter == false)
    }

    @Test func `a prompt with no arg is refused, because nothing could carry the value`() throws {
        // The arg names the key the typed text arrives under. Without it
        // the field would render and submit into nowhere, which is worse
        // than refusing the manifest — so this is an error at
        // `plugin validate` time, like an undeclared command source.
        #expect(throws: PluginManifestError.missingPromptArg) {
            _ = try body(#"{"kind":"list","source":"open","prompt":{"placeholder":"x"}}"#)
        }
        #expect(throws: PluginManifestError.missingPromptArg) {
            _ = try body(#"{"kind":"list","source":"open","prompt":{"arg":""}}"#)
        }
    }

    @Test func `a prompt can complete inline and remember what was submitted`() throws {
        // The two affordances that make a field feel like a URL bar
        // rather than a text box: it finishes the word, and it recalls
        // what you opened last time. Separate flags, because a settings
        // field wants neither and a search field may want only the first.
        let parsed = try body("""
        {"kind":"list","source":"open",
         "prompt":{"arg":"url","complete":true,"history":true}}
        """)
        guard case .list(let list) = parsed else {
            Issue.record("expected a list body"); return
        }
        #expect(list.prompt?.complete == true)
        #expect(list.prompt?.history == true)
    }

    @Test func `a prompt neither completes nor remembers unless it says so`() throws {
        let parsed = try body(#"{"kind":"list","source":"open","prompt":{"arg":"url"}}"#)
        guard case .list(let list) = parsed else {
            Issue.record("expected a list body"); return
        }
        #expect(list.prompt?.complete == false)
        #expect(list.prompt?.history == false)
    }

    @Test func `a panel without a prompt is unchanged`() throws {
        let parsed = try body(#"{"kind":"list","source":"open","rowAction":"highlight"}"#)
        #expect(parsed == .list(ListBody(source: "open", rowAction: .highlight)))
    }

    @Test func `the browser is told what to draw and which key to submit under`() throws {
        // The page renders the field from this, and posts the typed text
        // as `args[arg]` — so all four have to survive the projection.
        let manifest = try PluginManifest.parsing(json: Data("""
        {"name":"deeplink","version":"1.0.0",
         "contributes":{
           "commands":[{"id":"open","title":"Open","run":["node","bin/x.js"]}],
           "panels":[{"id":"open","title":"Deep Links","icon":"link",
             "body":{"kind":"list","source":"open","rowAction":"run",
                     "prompt":{"arg":"url","placeholder":"myapp://path",
                               "submit":"Open","filter":true}}}]}}
        """.utf8))
        let plugins = MockPlugins()
        given(plugins).all().willReturn([
            Plugin(root: URL(fileURLWithPath: "/tmp/deeplink"), manifest: manifest)
        ])

        let json = try plugins.listJSON
        let root = try #require(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        let panels = ((root["plugins"] as? [[String: Any]])?.first?["panels"] as? [[String: Any]]) ?? []
        let prompt = (panels.first?["body"] as? [String: Any])?["prompt"] as? [String: Any]

        #expect(prompt?["arg"] as? String == "url")
        #expect(prompt?["placeholder"] as? String == "myapp://path")
        #expect(prompt?["submit"] as? String == "Open")
        #expect(prompt?["filter"] as? Bool == true)
    }

    @Test func `a panel with no prompt projects none, so old panels are byte-identical`() throws {
        let manifest = try PluginManifest.parsing(json: Data("""
        {"name":"a11y","version":"1.0.0",
         "contributes":{
           "commands":[{"id":"audit","title":"Audit","run":["node","bin/x.js"]}],
           "panels":[{"id":"audit","title":"Audit","icon":"accessibility",
             "body":{"kind":"list","source":"audit","rowAction":"highlight"}}]}}
        """.utf8))
        let plugins = MockPlugins()
        given(plugins).all().willReturn([
            Plugin(root: URL(fileURLWithPath: "/tmp/a11y"), manifest: manifest)
        ])

        #expect(!(try plugins.listJSON).contains("prompt"))
    }
}
