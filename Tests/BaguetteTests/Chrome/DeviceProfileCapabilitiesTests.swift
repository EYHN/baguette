import Testing
import Foundation
@testable import BaguetteCore

/// Xcode 27 stopped publishing screen dimensions in `profile.plist`.
/// The `mainScreenWidth` / `mainScreenHeight` / `mainScreenScale` keys
/// that every Xcode ≤26 device type carried are gone — 124 of 124
/// profiles have them on Xcode 26, 0 of 124 on Xcode 27 — and the
/// numbers moved to a sibling `capabilities.plist` under a `displays`
/// list.
///
/// Only the 9-slice chrome path reads a screen size (the composite path
/// returns its baked PDF first), so the visible symptom is that every
/// 9-slice device loses its bezel while composite devices keep theirs.
///
/// Each device lists several displays — `tvOut` and `carPlay` at
/// 720×480, and a `scene` entry at 7680×4320. Only the `integrated`
/// one describes the device's own screen, so selecting on
/// `displayType` is what keeps a bezel from being sized off a
/// resizable-scene canvas.
@Suite("DeviceProfile screen size across Xcode versions")
struct DeviceProfileCapabilitiesTests {

    /// Xcode ≤26 shape: dimensions inline on the profile.
    private func legacyProfile() -> Data {
        let plist: [String: Any] = [
            "chromeIdentifier": "com.apple.dt.devicekit.chrome.tablet5",
            "mainScreenWidth": 1668,
            "mainScreenHeight": 2420,
            "mainScreenScale": 2,
        ]
        return try! PropertyListSerialization.data(
            fromPropertyList: plist, format: .binary, options: 0
        )
    }

    /// Xcode 27 shape: profile keeps the chrome id, drops the screen.
    private func modernProfile() -> Data {
        let plist: [String: Any] = [
            "chromeIdentifier": "com.apple.dt.devicekit.chrome.tablet5"
        ]
        return try! PropertyListSerialization.data(
            fromPropertyList: plist, format: .binary, options: 0
        )
    }

    /// Mirrors the real iPad Pro 11-inch (M4) capabilities: the
    /// integrated panel plus the decoys that must not be picked.
    private func capabilities() -> Data {
        let plist: [String: Any] = [
            "capabilities": [
                "displays": [
                    [
                        "displayType": "integrated",
                        "displayName": "LCD",
                        "width": 1668, "height": 2420, "scale": 2,
                    ],
                    [
                        "displayType": "tvOut",
                        "displayName": "TVOut",
                        "width": 720, "height": 480, "scale": 1,
                    ],
                    [
                        "displayType": "scene",
                        "displayName": "Resizable",
                        "width": 7680, "height": 4320, "scale": 3,
                    ],
                ]
            ]
        ]
        return try! PropertyListSerialization.data(
            fromPropertyList: plist, format: .binary, options: 0
        )
    }

    @Test func `reads the screen size from the profile on Xcode 26`() throws {
        let profile = try DeviceProfile.parsing(
            plistData: legacyProfile(), capabilitiesData: nil
        )

        #expect(profile.screenSize == Size(width: 834, height: 1210))
    }

    @Test func `reads the screen size from capabilities on Xcode 27`() throws {
        let profile = try DeviceProfile.parsing(
            plistData: modernProfile(), capabilitiesData: capabilities()
        )

        // 1668x2420 @2 — the same points the Xcode 26 profile gave.
        #expect(profile.screenSize == Size(width: 834, height: 1210))
    }

    @Test func `ignores non-integrated displays when reading capabilities`() throws {
        // The scene display is 7680x4320 and listed last; picking it
        // would size a bezel off a resizable canvas rather than the
        // device panel.
        let profile = try DeviceProfile.parsing(
            plistData: modernProfile(), capabilitiesData: capabilities()
        )

        #expect(profile.screenSize?.width == 834)
        #expect(profile.screenSize != Size(width: 2560, height: 1440))
    }

    @Test func `prefers the profile's own keys when both shapes are present`() throws {
        let profile = try DeviceProfile.parsing(
            plistData: legacyProfile(), capabilitiesData: capabilities()
        )

        #expect(profile.screenSize == Size(width: 834, height: 1210))
    }

    @Test func `has no screen size when neither shape carries one`() throws {
        let profile = try DeviceProfile.parsing(
            plistData: modernProfile(), capabilitiesData: nil
        )

        #expect(profile.screenSize == nil)
    }

    @Test func `still reads the chrome identifier on Xcode 27`() throws {
        let profile = try DeviceProfile.parsing(
            plistData: modernProfile(), capabilitiesData: capabilities()
        )

        #expect(profile.chromeIdentifier == "tablet5")
    }
}
