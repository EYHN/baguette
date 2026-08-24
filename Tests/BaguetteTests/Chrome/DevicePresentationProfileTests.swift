import Foundation
import Testing
@testable import BaguetteCore

@Suite("Device presentation profiles")
struct DevicePresentationProfileTests {
    @Test func `uses the integrated display dimensions and exact screen corners`() throws {
        let profile = try DevicePresentationProfile.parsing(
            plistData: Self.profile(chromeIdentifier: "com.apple.dt.devicekit.chrome.phone11"),
            capabilitiesData: Self.capabilities(
                idiom: "phone",
                displayType: "integrated",
                width: 1_206,
                height: 2_622,
                scale: 3,
                cornerRadius: 62
            ),
            deviceName: "iPhone 17 Pro"
        )

        #expect(profile.chromeIdentifier == "phone11")
        #expect(profile.formFactor == .phone)
        #expect(profile.screenSize == Size(width: 402, height: 874))
        #expect(profile.screenScale == 3)
        #expect(profile.screenCornerRadii == ScreenCornerRadii(all: 62))
    }

    @Test func `maps Apple TV onto DeviceKit tv chrome and its external display`() throws {
        let profile = try DevicePresentationProfile.parsing(
            plistData: Self.profile(chromeIdentifier: nil),
            capabilitiesData: Self.capabilities(
                idiom: "tv",
                displayType: "tvOut",
                width: 3_840,
                height: 2_160,
                scale: 2,
                cornerRadius: 0
            ),
            deviceName: "Apple TV 4K"
        )

        #expect(profile.chromeIdentifier == "tv")
        #expect(profile.formFactor == .tv)
        #expect(profile.screenSize == Size(width: 1_920, height: 1_080))
    }

    @Test func `keeps Apple Vision frameless while retaining its real display`() throws {
        let profile = try DevicePresentationProfile.parsing(
            plistData: Self.profile(chromeIdentifier: nil),
            capabilitiesData: Self.capabilities(
                idiom: "vision",
                displayType: "integrated",
                width: 3_840,
                height: 2_160,
                scale: 2,
                cornerRadius: 0
            ),
            deviceName: "Apple Vision Pro"
        )

        #expect(profile.chromeIdentifier == nil)
        #expect(profile.formFactor == .vision)
        #expect(profile.screenSize == Size(width: 1_920, height: 1_080))
        #expect(profile.screenCornerRadii == .zero)
    }

    @Test func `reads legacy numeric strings used by Apple TV profiles`() throws {
        let profile = try DevicePresentationProfile.parsing(
            plistData: Self.legacyProfile(
                chromeIdentifier: nil,
                width: "1920",
                height: "1080",
                scale: "1"
            ),
            capabilitiesData: nil,
            deviceName: "Apple TV 4K"
        )

        #expect(profile.chromeIdentifier == "tv")
        #expect(profile.formFactor == .tv)
        #expect(profile.screenSize == Size(width: 1_920, height: 1_080))
        #expect(profile.screenScale == 1)
    }

    @Test func `treats iPod touch as a phone when capabilities are absent`() throws {
        let profile = try DevicePresentationProfile.parsing(
            plistData: Self.legacyProfile(
                chromeIdentifier: "com.apple.dt.devicekit.chrome.phone4",
                width: 640,
                height: 1_136,
                scale: 2
            ),
            capabilitiesData: nil,
            deviceName: "iPod touch (7th generation)"
        )

        #expect(profile.formFactor == .phone)
        #expect(profile.screenSize == Size(width: 320, height: 568))
    }

    private static func profile(chromeIdentifier: String?) -> Data {
        var value: [String: Any] = [:]
        if let chromeIdentifier {
            value["chromeIdentifier"] = chromeIdentifier
        }
        return try! PropertyListSerialization.data(
            fromPropertyList: value,
            format: .xml,
            options: 0
        )
    }

    private static func legacyProfile(
        chromeIdentifier: String?,
        width: Any,
        height: Any,
        scale: Any
    ) -> Data {
        var value: [String: Any] = [
            "mainScreenWidth": width,
            "mainScreenHeight": height,
            "mainScreenScale": scale,
        ]
        if let chromeIdentifier {
            value["chromeIdentifier"] = chromeIdentifier
        }
        return try! PropertyListSerialization.data(
            fromPropertyList: value,
            format: .xml,
            options: 0
        )
    }

    private static func capabilities(
        idiom: String,
        displayType: String,
        width: Int,
        height: Int,
        scale: Int,
        cornerRadius: Double
    ) -> Data {
        let value: [String: Any] = [
            "capabilities": [
                "idiom": idiom,
                "displays": [[
                    "displayType": displayType,
                    "width": width,
                    "height": height,
                    "scale": scale,
                    "nativeOrientation": 0,
                    "cornerRadiusUL": cornerRadius,
                    "cornerRadiusUR": cornerRadius,
                    "cornerRadiusLL": cornerRadius,
                    "cornerRadiusLR": cornerRadius,
                ]],
            ],
        ]
        return try! PropertyListSerialization.data(
            fromPropertyList: value,
            format: .xml,
            options: 0
        )
    }
}
