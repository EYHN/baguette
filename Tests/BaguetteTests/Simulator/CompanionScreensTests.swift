import Foundation
import Testing

@testable import BaguetteCore

/// The extra screens a simulator can show beside its own glass: the
/// CarPlay external display, and the Apple Watch paired to it. The
/// browser rail offers a screen that is there and explains one that
/// isn't, so absence is an answer here — never an error.
@Suite("CompanionScreens")
struct CompanionScreensTests {

    @Test func `a device with neither screen reports both absent`() {
        let screens = CompanionScreens(externalSize: nil, watch: nil)

        #expect(screens.json == #"{"external":{"available":false},"watch":{"available":false}}"#)
    }

    /// The pane binds *the best external display*, whatever type the
    /// host calls it — a CarPlay screen, a TVOut, whatever the External
    /// Displays menu attached. Reporting its size lets the rail label
    /// what is actually on screen instead of promising CarPlay and
    /// showing a 800×480 TVOut under that name.
    @Test func `an attached external reports the size it bound`() {
        let screens = CompanionScreens(
            externalSize: Size(width: 800, height: 480), watch: nil
        )

        #expect(screens.json == """
            {"external":{"available":true,"height":480,"width":800},\
            "watch":{"available":false}}
            """)
    }

    @Test func `a non-integral size still round-trips as a number`() {
        let screens = CompanionScreens(
            externalSize: Size(width: 720.5, height: 480), watch: nil
        )
        let parsed = (try? JSONSerialization.jsonObject(with: Data(screens.json.utf8)))
            as? [String: Any]
        let external = parsed?["external"] as? [String: Any]
        #expect(external?["width"] as? Double == 720.5)
    }

    @Test func `a paired watch names itself so the rail can label and stream it`() {
        let screens = CompanionScreens(
            externalSize: nil,
            watch: PairedWatch(
                udid: "WATCH-1",
                name: "Apple Watch Series 11 (46mm)",
                state: .booted
            )
        )

        #expect(screens.json == """
            {"external":{"available":false},"watch":{"available":true,\
            "name":"Apple Watch Series 11 (46mm)","state":"Booted","udid":"WATCH-1"}}
            """)
    }

    @Test func `a paired watch that isn't booted is still available, and says so`() {
        let screens = CompanionScreens(
            externalSize: Size(width: 800, height: 480),
            watch: PairedWatch(udid: "WATCH-2", name: "Apple Watch Ultra 3", state: .shutdown)
        )

        #expect(screens.json == """
            {"external":{"available":true,"height":480,"width":800},"watch":{"available":true,\
            "name":"Apple Watch Ultra 3","state":"Shutdown","udid":"WATCH-2"}}
            """)
    }

    @Test func `a name carrying JSON punctuation stays one string`() {
        let screens = CompanionScreens(
            externalSize: nil,
            watch: PairedWatch(udid: "W", name: #"Watch "Test" \ 1"#, state: .booted)
        )

        let parsed = (try? JSONSerialization.jsonObject(with: Data(screens.json.utf8)))
            as? [String: Any]
        let watch = parsed?["watch"] as? [String: Any]
        #expect(watch?["name"] as? String == #"Watch "Test" \ 1"#)
    }
}
