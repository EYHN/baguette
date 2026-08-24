import Foundation
import Testing
@testable import BaguetteCore

@Suite("Device presentations")
struct DevicePresentationTests {
    @Test func `framed presentation keeps bezel pixels and screen geometry paired`() throws {
        let profile = DevicePresentationProfile(
            chromeIdentifier: "phone11",
            chromeIsOptional: false,
            formFactor: .phone,
            screenSize: Size(width: 402, height: 874),
            screenScale: 3,
            screenCornerRadii: ScreenCornerRadii(all: 62),
            nativeOrientation: 0
        )
        let chrome = DeviceChrome(
            identifier: "phone11",
            screenInsets: Insets(top: 18, left: 18, bottom: 18, right: 18),
            outerCornerRadius: 80,
            buttons: [],
            compositeImageName: nil
        )
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let assets = DeviceChromeAssets(
            chrome: chrome,
            composite: ChromeImage(
                data: png,
                size: Size(width: 442, height: 912)
            ),
            bareComposite: ChromeImage(
                data: png,
                size: Size(width: 438, height: 910)
            ),
            buttonMargins: Insets(top: 1, left: 1, bottom: 1, right: 3)
        )

        let snapshot = DevicePresentation.framed(
            profile: profile,
            assets: assets
        ).snapshot
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(snapshot.layoutJSON.utf8))
                as? [String: Any]
        )
        let viewport = try #require(json["viewport"] as? [String: Double])
        let screen = try #require(json["screen"] as? [String: Any])
        let corners = try #require(screen["cornerRadii"] as? [String: Double])

        #expect(snapshot.bezelPNG == png)
        #expect(json["presentation"] as? String == "bezel")
        #expect(json["formFactor"] as? String == "phone")
        #expect(viewport == ["width": 442, "height": 912])
        #expect(screen["x"] as? Double == 19)
        #expect(screen["y"] as? Double == 19)
        #expect(screen["width"] as? Double == 402)
        #expect(screen["height"] as? Double == 874)
        #expect(corners == [
            "topLeft": 62,
            "topRight": 62,
            "bottomLeft": 62,
            "bottomRight": 62,
        ])
    }

    @Test func `frameless presentation uses the entire real display`() throws {
        let profile = DevicePresentationProfile(
            chromeIdentifier: nil,
            chromeIsOptional: false,
            formFactor: .vision,
            screenSize: Size(width: 1_920, height: 1_080),
            screenScale: 2,
            screenCornerRadii: .zero,
            nativeOrientation: 0
        )

        let snapshot = DevicePresentation.frameless(profile: profile).snapshot
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(snapshot.layoutJSON.utf8))
                as? [String: Any]
        )
        let viewport = try #require(json["viewport"] as? [String: Double])
        let screen = try #require(json["screen"] as? [String: Any])

        #expect(snapshot.bezelPNG == nil)
        #expect(json["presentation"] as? String == "frameless")
        #expect(json["formFactor"] as? String == "vision")
        #expect(viewport == ["width": 1_920, "height": 1_080])
        #expect(screen["x"] as? Double == 0)
        #expect(screen["y"] as? Double == 0)
        #expect(screen["width"] as? Double == 1_920)
        #expect(screen["height"] as? Double == 1_080)
    }
}
