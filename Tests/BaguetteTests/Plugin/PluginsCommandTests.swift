import Testing
import Foundation
@testable import BaguetteCore

/// Text projections for `baguette plugin list | show | validate`.
/// The commands themselves are thin shells over these pure functions
/// plus `FileSystemPlugins`, so the formatting is covered here and the
/// filesystem walk is covered in `FileSystemPluginsTests`.
@Suite("PluginsCommand")
struct PluginsCommandTests {

    // MARK: - list

    @Test func `listing names each plugin with its version`() throws {
        let text = PluginsCommand.listing([
            Self.plugin(name: "a11y", version: "1.2.0"),
            Self.plugin(name: "expo", version: "0.3.1"),
        ])
        #expect(text.contains("a11y  1.2.0"))
        #expect(text.contains("expo  0.3.1"))
    }

    @Test func `listing says so when nothing is installed`() throws {
        // An empty toolbar with no explanation reads as a bug. Name
        // the roots so the user knows where a plugin would go.
        let text = PluginsCommand.listing([])
        #expect(text.contains("No plugins installed"))
        #expect(text.contains(".baguette/plugins"))
    }

    // MARK: - show

    @Test func `show spells out what a plugin contributes before you trust it`() throws {
        // This is the pre-install inspection step: a manifest is data,
        // so baguette can say exactly what a plugin would add without
        // running a line of it.
        let text = PluginsCommand.detail(Self.plugin(name: "a11y", version: "1.2.0"))
        #expect(text.contains("a11y:audit"))
        #expect(text.contains("Run audit"))
        #expect(text.contains("node bin/audit.js"))
    }

    @Test func `show names the capabilities a plugin may use`() throws {
        // The security-relevant line — what this plugin can ask
        // baguette to do, before you install it.
        let text = PluginsCommand.detail(
            Self.plugin(name: "expo", version: "1.0.0", capabilities: [.input])
        )
        #expect(text.contains("capabilities: input"))
    }

    @Test func `show says so when a plugin asks for nothing`() throws {
        let text = PluginsCommand.detail(Self.plugin(name: "inert", version: "1.0.0"))
        #expect(text.contains("capabilities: none"))
    }

    // MARK: - validate

    @Test func `validate accepts a well-formed manifest and counts its contributions`() throws {
        let outcome = PluginsCommand.validate(json: Self.manifestJSON)
        #expect(outcome == .valid(name: "a11y", commands: 1, panels: 1))
    }

    @Test func `validate explains exactly why a manifest was rejected`() throws {
        // The failure mode of a misplaced or mistyped manifest is a
        // silent no-op, which is why this verb exists at all.
        let outcome = PluginsCommand.validate(json: Data("""
        { "name": "x", "version": "1.0.0", "apiVersion": 1,
          "contributes": { "panels": [
            { "id": "p", "title": "P", "icon": "list",
              "body": { "kind": "list", "source": "gone" } } ] } }
        """.utf8))
        #expect(outcome == .invalid(
            reason: PluginManifestError.unknownCommandSource(id: "gone").description
        ))
    }

    @Test func `validate reports a mistyped icon even though it no longer refuses one`() throws {
        // Icons degrade so a plugin naming a future glyph still runs.
        // That must not swallow the authoring feedback: "nope" is a
        // typo, and validate is the one place an author finds out.
        let outcome = PluginsCommand.validate(json: Data("""
        { "name": "x", "version": "1.0.0", "apiVersion": 1,
          "contributes": {
            "commands": [ { "id": "go", "title": "Go", "run": ["true"] } ],
            "panels": [
              { "id": "p", "title": "P", "icon": "nope",
                "body": { "kind": "list", "source": "go" } } ] } }
        """.utf8))
        #expect(outcome == .valid(
            name: "x", commands: 1, panels: 1,
            warnings: [PluginManifestWarning.unknownIcon(name: "nope").description]
        ))
    }

    // MARK: - helpers

    static func plugin(
        name: String, version: String, capabilities: [PluginCapability] = []
    ) -> Plugin {
        Plugin(
            root: URL(fileURLWithPath: "/tmp/plugins/\(name)"),
            manifest: PluginManifest(
                name: name, version: version, apiVersion: 1,
                capabilities: capabilities,
                commands: [
                    PluginCommand(id: "audit", title: "Run audit", run: ["node", "bin/audit.js"])
                ]
            )
        )
    }

    static let manifestJSON = Data("""
    {
      "name": "a11y", "version": "1.0.0", "apiVersion": 1,
      "contributes": {
        "commands": [ { "id": "audit", "title": "Run audit", "run": ["node", "bin/audit.js"] } ],
        "panels": [
          { "id": "audit", "title": "Accessibility", "icon": "accessibility",
            "body": { "kind": "list", "source": "audit", "rowAction": "highlight" } }
        ]
      }
    }
    """.utf8)
}
