import Testing
import Foundation
@testable import BaguetteCore

/// Pure-value coverage for `AppBundle` — the thing the user means when
/// they say "install an app." `AppBundle.at(_:)` is the classification:
/// it answers "is this file an app I can install?" by extension, with
/// no disk access (so the serve route can reject before reading a
/// 60 MB body). `installArguments` is the argv tail handed to
/// `xcrun simctl install <udid> <path>`.
@Suite("AppBundle")
struct AppBundleTests {

    @Test func `an .ipa file is an installable app`() {
        let url = URL(fileURLWithPath: "/tmp/MyApp.ipa")
        #expect(AppBundle.at(url) == AppBundle(path: url))
    }

    @Test func `a .app bundle is an installable app`() {
        let url = URL(fileURLWithPath: "/tmp/MyApp.app")
        #expect(AppBundle.at(url) == AppBundle(path: url))
    }

    @Test func `the .ipa extension match is case-insensitive`() {
        let url = URL(fileURLWithPath: "/tmp/MyApp.IPA")
        #expect(AppBundle.at(url) == AppBundle(path: url))
    }

    @Test func `a photo is not an app`() {
        #expect(AppBundle.at(URL(fileURLWithPath: "/tmp/photo.png")) == nil)
    }

    @Test func `a generic document is not an app`() {
        #expect(AppBundle.at(URL(fileURLWithPath: "/tmp/notes.pdf")) == nil)
    }

    @Test func `an extension-less file is not an app`() {
        #expect(AppBundle.at(URL(fileURLWithPath: "/tmp/Makefile")) == nil)
    }

    @Test func `installArguments projects the simctl install argv tail`() {
        let app = AppBundle(path: URL(fileURLWithPath: "/tmp/My App.ipa"))
        #expect(app.installArguments(udid: "U") == ["simctl", "install", "U", "/tmp/My App.ipa"])
    }
}
