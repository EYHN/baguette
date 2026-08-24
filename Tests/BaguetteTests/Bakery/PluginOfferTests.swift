import Testing
import Foundation
@testable import BaguetteCore

/// What a trusted bakery is offering right now, and whether you
/// already have it. Pure join — the browser's plugin shelf renders
/// exactly this, so the "is it installed" rule lives here rather than
/// being re-derived in JavaScript.
@Suite("PluginOffer")
struct PluginOfferTests {

    @Test func `a bakery's menu becomes its offers, in the order the bakery listed them`() {
        // Menu order is the bakery author's, and there is no reason to
        // override it — a bakery that puts its headline plugin first
        // meant to.
        let offers = PluginOffer.list(
            of: Self.bakery(plugins: ["deeplink", "a11y", "expo"]), installed: []
        )
        #expect(offers.map(\.name) == ["deeplink", "a11y", "expo"])
    }

    @Test func `a plugin already on this machine is marked installed`() {
        let offers = PluginOffer.list(
            of: Self.bakery(plugins: ["deeplink", "a11y"]), installed: ["a11y"]
        )
        #expect(offers == [
            PluginOffer(name: "deeplink", installed: false),
            PluginOffer(name: "a11y", installed: true),
        ])
    }

    @Test func `a plugin installed from somewhere else still counts as installed`() {
        // The shelf answers "do I have this", not "did I get it from
        // here". `a11y` ships inside the binary and is in nobody's
        // `installed.json`, so a bakery offering it must not show an
        // Install button that would shadow the bundled one.
        let offers = PluginOffer.list(of: Self.bakery(plugins: ["a11y"]), installed: ["a11y"])
        #expect(offers.first?.installed == true)
    }

    @Test func `a bakery that offers nothing has no offers`() {
        // Possible after a menu shrinks and the pin hasn't been moved.
        #expect(PluginOffer.list(of: Self.bakery(plugins: []), installed: ["a11y"]).isEmpty)
    }

    static func bakery(plugins: [String]) -> Bakery {
        Bakery(
            id: "github.com/acme/tools", url: "https://github.com/acme/tools.git",
            commit: "c0ffee", plugins: plugins, addedAt: "2026-08-19T00:00:00Z"
        )
    }
}
