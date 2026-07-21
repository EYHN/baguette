import Testing
import Foundation
@testable import BaguetteCore

/// Pure-value coverage for `MediaItem` — the thing the user means when
/// they drag a photo or clip onto a device and think "add this to my
/// camera roll." `MediaItem.at(_:)` classifies by extension (no disk
/// access); `addMediaArguments` projects the argv tail for
/// `xcrun simctl addmedia <udid> <path>`.
@Suite("MediaItem")
struct MediaItemTests {

    @Test func `common image extensions are media`() {
        for ext in ["png", "jpg", "jpeg", "gif", "heic", "heif"] {
            let url = URL(fileURLWithPath: "/tmp/shot.\(ext)")
            #expect(MediaItem.at(url) == MediaItem(path: url))
        }
    }

    @Test func `common video extensions are media`() {
        for ext in ["mov", "mp4", "m4v"] {
            let url = URL(fileURLWithPath: "/tmp/clip.\(ext)")
            #expect(MediaItem.at(url) == MediaItem(path: url))
        }
    }

    @Test func `the extension match is case-insensitive`() {
        let url = URL(fileURLWithPath: "/tmp/shot.PNG")
        #expect(MediaItem.at(url) == MediaItem(path: url))
    }

    @Test func `an app is not media`() {
        #expect(MediaItem.at(URL(fileURLWithPath: "/tmp/MyApp.ipa")) == nil)
    }

    @Test func `a generic document is not media`() {
        #expect(MediaItem.at(URL(fileURLWithPath: "/tmp/notes.pdf")) == nil)
    }

    @Test func `addMediaArguments projects the simctl addmedia argv tail`() {
        let media = MediaItem(path: URL(fileURLWithPath: "/tmp/My Clip.mov"))
        #expect(media.addMediaArguments(udid: "U") == ["simctl", "addmedia", "U", "/tmp/My Clip.mov"])
    }
}
