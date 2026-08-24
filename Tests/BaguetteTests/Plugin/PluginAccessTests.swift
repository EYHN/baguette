import Testing
import Foundation
@testable import BaguetteCore

/// The question every request asks before a handler runs: is this a
/// plugin, and if so may it be here?
///
/// Three answers, not two. `anonymous` is the important one — a request
/// with no grant isn't claiming to be a plugin at all, so it must fall
/// through to the browser-trust check exactly as it did before plugins
/// existed. Collapsing that into "refused" would break `curl` and the
/// browser; collapsing it into "granted" would make the grant optional,
/// which is the same as not having one.
@Suite("PluginAccess")
struct PluginAccessTests {

    @Test func `a plugin reaches a route its manifest declared`() {
        let grants = PluginGrants()
        let token = grants.issue(plugin: "expo", capabilities: [.input])
        #expect(
            PluginAccess.decide(token: token, path: "/simulators/U/input", grants: grants)
                == .granted
        )
    }

    @Test func `a plugin is refused a route it did not declare, and the refusal names it`() {
        // The a11y plugin reads the screen; it must not be able to drive
        // the device. The message names the missing capability so the
        // author fixes the manifest instead of guessing.
        let grants = PluginGrants()
        let token = grants.issue(plugin: "a11y", capabilities: [.describeUI])
        let access = PluginAccess.decide(token: token, path: "/simulators/U/input", grants: grants)
        guard case .refused(let message) = access else {
            Issue.record("expected .refused, got \(access)"); return
        }
        #expect(message == #"this plugin did not declare the "input" capability"#)
    }

    @Test func `a plugin holding one capability cannot reach a route gated by another`() {
        let grants = PluginGrants()
        let token = grants.issue(plugin: "a11y", capabilities: [.describeUI])
        for path in ["/simulators/U/screenshot.jpg", "/simulators/U/apps",
                     "/simulators/U/media", "/simulators.json",
                     "/simulators/U/openurl", "/simulators/U/schemes.json"] {
            guard case .refused = PluginAccess.decide(token: token, path: path, grants: grants) else {
                Issue.record("\(path) should be refused"); return
            }
        }
        #expect(
            PluginAccess.decide(token: token, path: "/simulators/U/describe-ui.json", grants: grants)
                == .granted
        )
    }

    @Test func `a route no capability unlocks is closed even to a plugin that declared everything`() {
        // Least privilege has to hold at the edges too: declaring the
        // whole set still doesn't reach a route outside the table.
        let grants = PluginGrants()
        let token = grants.issue(plugin: "greedy", capabilities: PluginCapability.allCases)
        for path in [
            "/simulators/U/boot",
            // The browser's drag-and-drop upload, which decides between
            // installing an app and adding a photo from the bytes. No
            // manifest can ask for it — plugins say which they mean.
            "/simulators/U/files",
        ] {
            let access = PluginAccess.decide(token: token, path: path, grants: grants)
            guard case .refused(let message) = access else {
                Issue.record("\(path) should be refused, got \(access)"); return
            }
            #expect(message.contains("no capability"))
        }
    }

    @Test func `a deep-link plugin reaches both its routes and nothing else`() {
        // `open-url` is one capability over one surface: see what's
        // registered, open one. It must not carry the authority to
        // install an app, which is the neighbouring `apps` power.
        let grants = PluginGrants()
        let token = grants.issue(plugin: "deeplink", capabilities: [.openURL])
        for path in ["/simulators/U/openurl", "/simulators/U/schemes.json"] {
            #expect(
                PluginAccess.decide(token: token, path: path, grants: grants) == .granted,
                "\(path) should be granted"
            )
        }
        guard case .refused(let message) = PluginAccess.decide(
            token: token, path: "/simulators/U/apps", grants: grants
        ) else {
            Issue.record("open-url must not reach the app-install route"); return
        }
        #expect(message == #"this plugin did not declare the "apps" capability"#)
    }

    // MARK: - callers that aren't plugins

    @Test func `a request with no grant is anonymous so browser trust still decides`() {
        // `curl` and the browser present no token. They must be handled
        // by the origin checks, not by the capability table.
        let grants = PluginGrants()
        #expect(
            PluginAccess.decide(token: nil, path: "/simulators/U/input", grants: grants)
                == .anonymous
        )
        #expect(
            PluginAccess.decide(token: "", path: "/simulators/U/input", grants: grants)
                == .anonymous
        )
    }

    @Test func `an anonymous caller is anonymous on an unmapped route too`() {
        // Closing unmapped routes applies to plugins. A browser opening
        // the page must not be caught by it.
        let grants = PluginGrants()
        #expect(
            PluginAccess.decide(token: nil, path: "/simulators/U/boot", grants: grants)
                == .anonymous
        )
    }

    @Test func `a revoked grant is refused, not waved through as anonymous`() {
        // Otherwise the way to escape the capability check would be to
        // present a stale token — or any garbage — instead of a real one.
        let grants = PluginGrants()
        let token = grants.issue(plugin: "expo", capabilities: [.input])
        grants.revoke(token)
        guard case .refused = PluginAccess.decide(
            token: token, path: "/simulators/U/input", grants: grants
        ) else {
            Issue.record("a revoked grant must be refused"); return
        }
    }

    @Test func `an invented token is refused rather than treated as no token`() {
        let grants = PluginGrants()
        guard case .refused = PluginAccess.decide(
            token: "made-up", path: "/simulators/U/input", grants: grants
        ) else {
            Issue.record("an unknown grant must be refused"); return
        }
    }
}
