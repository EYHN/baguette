import Testing
import Foundation
@testable import BaguetteCore

@Suite("PluginGrants")
struct PluginGrantsTests {

    @Test func `a grant resolves to exactly the plugin's declared capabilities`() throws {
        let grants = PluginGrants()
        let token = grants.issue(plugin: "a11y", capabilities: [.describeUI, .screenshot])
        #expect(grants.capabilities(for: token) == [.describeUI, .screenshot])
    }

    @Test func `each grant gets its own unguessable token`() throws {
        let grants = PluginGrants()
        let a = grants.issue(plugin: "a11y", capabilities: [.describeUI])
        let b = grants.issue(plugin: "expo", capabilities: [.input])
        #expect(a != b)
        #expect(a.count >= 32)
        // A token is bound to its own plugin's grant, not the other's.
        #expect(grants.capabilities(for: a) == [.describeUI])
        #expect(grants.capabilities(for: b) == [.input])
    }

    @Test func `a revoked token stops working`() throws {
        // The grant lives exactly as long as the command invocation, so
        // a leaked token is useless once the command exits.
        let grants = PluginGrants()
        let token = grants.issue(plugin: "a11y", capabilities: [.describeUI])
        grants.revoke(token)
        #expect(grants.capabilities(for: token) == nil)
    }

    @Test func `an unknown token grants nothing`() throws {
        let grants = PluginGrants()
        #expect(grants.capabilities(for: "made-up") == nil)
    }

    // MARK: - the authorization question

    @Test func `a token is allowed a capability its plugin declared`() throws {
        let grants = PluginGrants()
        let token = grants.issue(plugin: "expo", capabilities: [.input])
        #expect(grants.allows(token: token, capability: .input))
    }

    @Test func `a token is refused a capability its plugin did not declare`() throws {
        // The whole point: the a11y plugin reads the screen, so it must
        // not be able to drive the device.
        let grants = PluginGrants()
        let token = grants.issue(plugin: "a11y", capabilities: [.describeUI])
        #expect(!grants.allows(token: token, capability: .input))
    }

    @Test func `no token is refused everything`() throws {
        let grants = PluginGrants()
        #expect(!grants.allows(token: nil, capability: .describeUI))
        #expect(!grants.allows(token: "", capability: .describeUI))
    }
}
