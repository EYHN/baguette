import Testing
import Foundation
@testable import BaguetteCore

/// Where baguette keeps installed plugins, trusted bakeries and the
/// clone cache. One resolver so the CLI, the server and the plugin
/// scanner can't disagree about which directory they mean — a
/// disagreement would show up as "I installed it and the rail is empty".
///
/// `.serialized` because `setenv` is process-global.
@Suite("BaguetteHome", .serialized)
struct BaguetteHomeTests {

    /// Puts `BAGUETTE_HOME` back exactly as it was found.
    ///
    /// Unsetting it unconditionally is not the same thing: a developer
    /// who runs the suite with `BAGUETTE_HOME` already exported would
    /// lose it for every test that ran afterwards, and the value can't
    /// be recovered once it's gone.
    final class HomeOverride {
        private let previous: String?

        init(_ value: String?) {
            previous = ProcessInfo.processInfo.environment["BAGUETTE_HOME"]
            if let value {
                setenv("BAGUETTE_HOME", value, 1)
            } else {
                unsetenv("BAGUETTE_HOME")
            }
        }

        deinit {
            if let previous {
                setenv("BAGUETTE_HOME", previous, 1)
            } else {
                unsetenv("BAGUETTE_HOME")
            }
        }
    }

    @Test func `the override wins so tests and sandboxes never touch the real home`() {
        let restore = HomeOverride("/tmp/baguette-home-test")
        defer { _ = restore }

        #expect(BaguetteHome.url.path == "/tmp/baguette-home-test")
    }

    @Test func `an empty override is ignored rather than resolving to nothing`() {
        // `BAGUETTE_HOME=` in a shell profile shouldn't silently point
        // the whole install at the filesystem root.
        let restore = HomeOverride("")
        defer { _ = restore }

        #expect(BaguetteHome.url.path == NSHomeDirectory() + "/.baguette")
    }

    @Test func `the default is a dotfile directory in the user's home`() {
        let restore = HomeOverride(nil)
        defer { _ = restore }

        #expect(BaguetteHome.url.path == NSHomeDirectory() + "/.baguette")
    }

    @Test func `installed plugins live under the home, wherever it points`() {
        // The scanner root and the install target are the same path by
        // construction, not by two places agreeing on a string.
        let restore = HomeOverride("/tmp/baguette-home-test")
        defer { _ = restore }

        #expect(BaguetteHome.pluginsRoot.path == "/tmp/baguette-home-test/plugins")
        #expect(BaguetteHome.pluginsRoot.deletingLastPathComponent().path == BaguetteHome.url.path)
    }
}
