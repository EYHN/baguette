import Testing
import Foundation
@testable import BaguetteCore

/// Which capability each plugin-reachable route demands.
///
/// The table is deliberately a *closed* list: a path it doesn't name is
/// unreachable by a plugin, so a route added to the server later is
/// locked out until someone names it here. The drift direction is
/// "plugins can't get in yet", never "plugins got in silently".
@Suite("PluginRoute")
struct PluginRouteTests {

    @Test func `reading the screen demands screenshot`() {
        #expect(PluginRoute.capability(path: "/simulators/U/screenshot.jpg") == .screenshot)
    }

    @Test func `reading the accessibility tree demands describe-ui`() {
        #expect(PluginRoute.capability(path: "/simulators/U/describe-ui.json") == .describeUI)
    }

    @Test func `driving the device demands input`() {
        #expect(PluginRoute.capability(path: "/simulators/U/input") == .input)
    }

    @Test func `the status bar demands status-bar however it is addressed`() {
        // One capability covers read, override and clear — they're the
        // same authority over the same surface, and GET/POST/DELETE
        // share the path.
        #expect(PluginRoute.capability(path: "/simulators/U/status-bar") == .statusBar)
    }

    @Test func `the simulated location demands location`() {
        #expect(PluginRoute.capability(path: "/simulators/U/location") == .location)
    }

    @Test func `installing an app and adding media are separate powers`() {
        // Putting a photo in the library and installing an executable
        // are not the same authority, and bundling them meant a plugin
        // that wanted to seed test images had to be trusted to install
        // software.
        #expect(PluginRoute.capability(path: "/simulators/U/apps") == .apps)
        #expect(PluginRoute.capability(path: "/simulators/U/media") == .media)
    }

    @Test func `the browser's drag-and-drop upload is closed to plugins`() {
        // `/files` routes by extension, so the capability it demands
        // would depend on the bytes rather than the path — and a
        // content-dependent check is exactly what this table exists to
        // avoid. Plugins name the kind they mean.
        #expect(PluginRoute.capability(path: "/simulators/U/files") == nil)
    }

    @Test func `the log feed demands logs`() {
        #expect(PluginRoute.capability(path: "/simulators/U/logs") == .logs)
    }

    @Test func `listing devices demands simulators`() {
        #expect(PluginRoute.capability(path: "/simulators.json") == .simulators)
    }

    @Test func `appearance, contrast and text size demand interface`() {
        // One capability for the whole `simctl ui` family: a plugin that
        // can darken the screen can already restyle it, so splitting
        // read from write would be a distinction without a difference.
        #expect(PluginRoute.capability(path: "/simulators/U/interface") == .interface)
        #expect(PluginRoute.capability(path: "/simulators/U/interface.json") == .interface)
    }

    @Test func `opening a link and listing schemes demand open-url`() {
        // One capability for the pair, on the `interface` precedent: a
        // plugin that can open *any* URL is not meaningfully restrained
        // by hiding the list of which ones an app registered.
        #expect(PluginRoute.capability(path: "/simulators/U/openurl") == .openURL)
        #expect(PluginRoute.capability(path: "/simulators/U/schemes.json") == .openURL)
    }

    @Test func `opening a link is not covered by the app-install capability`() {
        // `apps` puts an executable on the device; `open-url` launches
        // one that's already there. A plugin that only wants to fire a
        // deep link must not have to be trusted to install software.
        #expect(PluginCapability.openURL != .apps)
        #expect(PluginRoute.capability(path: "/simulators/U/openurl") != .apps)
    }

    @Test func `a real udid is carried in the path like any other segment`() {
        #expect(
            PluginRoute.capability(path: "/simulators/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/input")
                == .input
        )
    }

    @Test func `a query string doesn't hide the route`() {
        #expect(
            PluginRoute.capability(path: "/simulators/U/screenshot.jpg?scale=0.5") == .screenshot
        )
    }

    // MARK: - closed by default

    @Test func `device lifecycle is unreachable by a plugin`() {
        // No capability spells "boot and shut down devices", so no
        // manifest can ask for it and every plugin token is refused.
        #expect(PluginRoute.capability(path: "/simulators/U/boot") == nil)
        #expect(PluginRoute.capability(path: "/simulators/U/shutdown") == nil)
    }

    @Test func `routes no capability names are unreachable by a plugin`() {
        for path in [
            "/simulators/U/orientation",
            "/simulators/U/camera-source",
            "/simulators/U/render-3d.png",
            "/simulators/U/chrome.json",
            "/simulators/U/bezel.png",
            "/simulators/U/3d-model.json",
        ] {
            #expect(PluginRoute.capability(path: path) == nil, "\(path) should be closed")
        }
    }

    @Test func `the plugin and bakery surfaces are browser-facing, not plugin-facing`() {
        // A plugin must not be able to run other plugins, or install new
        // ones — that's the user's consent to give, from the browser.
        #expect(PluginRoute.capability(path: "/plugins.json") == nil)
        #expect(PluginRoute.capability(path: "/plugins/a11y/commands/audit") == nil)
        #expect(PluginRoute.capability(path: "/bakeries/install") == nil)
    }

    @Test func `the pages and static assets are not plugin routes`() {
        #expect(PluginRoute.capability(path: "/") == nil)
        #expect(PluginRoute.capability(path: "/simulators") == nil)
        #expect(PluginRoute.capability(path: "/simulators/U") == nil)
        #expect(PluginRoute.capability(path: "/sim-plugins.js") == nil)
    }
}
