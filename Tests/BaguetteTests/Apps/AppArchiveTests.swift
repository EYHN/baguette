import Testing
import Foundation
@testable import BaguetteCore

/// Pure-value coverage for `AppArchive` — a zip that carries an app.
/// The browser can't upload a folder-form `.app` bundle as one file, so
/// it packs the bundle into a zip and posts that instead; a user-zipped
/// `.app` arrives the same way. `AppArchive.at(_:)` classifies by
/// extension with no disk access (so the serve route can reject before
/// reading the body), `extractArguments(to:)` projects the
/// `ditto -x -k` argv tail, and `installableApp(amongExtracted:)`
/// answers "which entry is the app?" purely over the extracted
/// top-level names — exactly one `.app`, junk ignored, ambiguity
/// refused.
@Suite("AppArchive")
struct AppArchiveTests {

    // MARK: classification

    @Test func `a .zip file is an app archive`() {
        let url = URL(fileURLWithPath: "/tmp/MyApp.app.zip")
        #expect(AppArchive.at(url) == AppArchive(path: url))
    }

    @Test func `the .zip extension match is case-insensitive`() {
        let url = URL(fileURLWithPath: "/tmp/MyApp.ZIP")
        #expect(AppArchive.at(url) == AppArchive(path: url))
    }

    @Test func `an .ipa is not an app archive — it installs directly`() {
        #expect(AppArchive.at(URL(fileURLWithPath: "/tmp/MyApp.ipa")) == nil)
    }

    @Test func `a bare .app path is not an app archive`() {
        #expect(AppArchive.at(URL(fileURLWithPath: "/tmp/MyApp.app")) == nil)
    }

    @Test func `media is not an app archive`() {
        #expect(AppArchive.at(URL(fileURLWithPath: "/tmp/shot.png")) == nil)
    }

    // MARK: extraction argv

    @Test func `extractArguments projects the ditto -x -k argv tail`() {
        let archive = AppArchive(path: URL(fileURLWithPath: "/tmp/up/My App.app.zip"))
        let dest = URL(fileURLWithPath: "/tmp/extract-1")
        #expect(archive.extractArguments(to: dest)
            == ["-x", "-k", "/tmp/up/My App.app.zip", "/tmp/extract-1"])
    }

    // MARK: locating the app among extracted entries

    @Test func `a single top-level .app is the installable app`() {
        #expect(AppArchive.installableApp(amongExtracted: ["MyApp.app"]) == "MyApp.app")
    }

    @Test func `the .app entry match is case-insensitive`() {
        #expect(AppArchive.installableApp(amongExtracted: ["MyApp.APP"]) == "MyApp.APP")
    }

    @Test func `Finder junk and dotfiles are ignored when locating the app`() {
        #expect(AppArchive.installableApp(
            amongExtracted: ["__MACOSX", ".DS_Store", "MyApp.app"]
        ) == "MyApp.app")
    }

    @Test func `a zip with no .app inside has no installable app`() {
        #expect(AppArchive.installableApp(amongExtracted: ["readme.txt", "assets"]) == nil)
    }

    @Test func `an empty archive has no installable app`() {
        #expect(AppArchive.installableApp(amongExtracted: []) == nil)
    }

    @Test func `two .app bundles are ambiguous and refused`() {
        #expect(AppArchive.installableApp(
            amongExtracted: ["One.app", "Two.app"]
        ) == nil)
    }

    // MARK: declared uncompressed size (pre-flight zip-bomb check)

    @Test func `declared uncompressed bytes sum across the central directory`() {
        let zip = ZipFixture.archive(declaring: [
            ("MyApp.app/Info.plist", 100), ("MyApp.app/MyApp", 200),
        ])
        #expect(AppArchive.declaredUncompressedBytes(in: zip) == 300)
    }

    @Test func `the end record is found behind a trailing archive comment`() {
        let zip = ZipFixture.archive(
            declaring: [("MyApp.app/MyApp", 64)],
            comment: Data("signed by tooling".utf8)
        )
        #expect(AppArchive.declaredUncompressedBytes(in: zip) == 64)
    }

    @Test func `an empty archive declares zero bytes`() {
        #expect(AppArchive.declaredUncompressedBytes(in: ZipFixture.archive(declaring: [])) == 0)
    }

    @Test func `bytes without an end-of-central-directory record are not a zip`() {
        #expect(AppArchive.declaredUncompressedBytes(in: Data("not a zip at all".utf8)) == nil)
    }

    @Test func `a central directory pointing outside the bytes is unreadable`() {
        var zip = ZipFixture.archive(declaring: [("MyApp.app/MyApp", 64)])
        let eocd = zip.count - 22
        zip.replaceSubrange((eocd + 16)..<(eocd + 20), with: [0xFF, 0xFF, 0xFF, 0x7F])
        #expect(AppArchive.declaredUncompressedBytes(in: zip) == nil)
    }

    @Test func `an entry count past the central directory's end is unreadable`() {
        var zip = ZipFixture.archive(declaring: [("MyApp.app/MyApp", 64)])
        let eocd = zip.count - 22
        zip[eocd + 10] = 2   // claims two entries; only one exists
        #expect(AppArchive.declaredUncompressedBytes(in: zip) == nil)
    }
}
