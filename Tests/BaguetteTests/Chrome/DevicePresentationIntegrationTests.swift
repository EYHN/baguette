import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import BaguetteCore

private let devicePresentationAssetsAvailable =
    FileManager.default.fileExists(
        atPath: "/Library/Developer/CoreSimulator/Profiles/DeviceTypes"
    )
    && FileManager.default.fileExists(
        atPath: "/Library/Developer/DeviceKit/Chrome"
    )

@Suite(
    "Device presentations (installed DeviceKit)",
    .enabled(if: devicePresentationAssetsAvailable)
)
struct DevicePresentationIntegrationTests {
    @Test func `every installed device type has an exact presentation`() throws {
        let root =
            "/Library/Developer/CoreSimulator/Profiles/DeviceTypes"
        let deviceNames = try FileManager.default.contentsOfDirectory(
            atPath: root
        )
        .filter { $0.hasSuffix(".simdevicetype") }
        .map { String($0.dropLast(".simdevicetype".count)) }
        .sorted()

        #expect(deviceNames.count >= 124)

        let store = FileSystemChromeStore()
        let presentations = LiveDevicePresentations(
            store: store,
            rasterizer: CoreGraphicsPDFRasterizer()
        )

        for deviceName in deviceNames {
            let profile = try DevicePresentationProfile.parsing(
                plistData: store.profilePlistData(deviceName: deviceName),
                capabilitiesData: try? store.capabilitiesPlistData(
                    deviceName: deviceName
                ),
                deviceName: deviceName
            )
            let snapshot = try presentations
                .presentation(forDeviceName: deviceName)
                .snapshot
            let layout = try Self.layout(snapshot.layoutJSON)

            #expect(
                layout.screen.size == profile.screenSize,
                "\(deviceName) screen \(layout.screen.size) != profile \(profile.screenSize)"
            )
            #expect(
                layout.screen.origin.x >= 0
                    && layout.screen.origin.y >= 0
                    && layout.screen.origin.x + layout.screen.size.width
                        <= layout.viewport.width
                    && layout.screen.origin.y + layout.screen.size.height
                        <= layout.viewport.height,
                "\(deviceName) screen lies outside viewport"
            )

            if snapshot.bezelPNG == nil {
                #expect(
                    profile.chromeIdentifier == nil || profile.chromeIsOptional,
                    "\(deviceName) unexpectedly lost a required DeviceKit bezel"
                )
                #expect(layout.presentation == "frameless")
                #expect(layout.screen == Rect(
                    origin: Point(x: 0, y: 0),
                    size: layout.viewport
                ))
            } else {
                let png = try #require(
                    snapshot.bezelPNG,
                    "\(deviceName) should have a DeviceKit bezel"
                )
                #expect(layout.presentation == "bezel")
                #expect(
                    try Self.imageSize(png) == layout.viewport,
                    "\(deviceName) PNG pixels do not match viewport"
                )
            }
        }
    }

    private struct Layout {
        let presentation: String
        let viewport: Size
        let screen: Rect
    }

    private static func layout(_ json: String) throws -> Layout {
        let root = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8))
                as? [String: Any]
        )
        let viewport = try #require(root["viewport"] as? [String: Any])
        let screen = try #require(root["screen"] as? [String: Any])
        return Layout(
            presentation: try #require(root["presentation"] as? String),
            viewport: Size(
                width: try #require(viewport["width"] as? Double),
                height: try #require(viewport["height"] as? Double)
            ),
            screen: Rect(
                origin: Point(
                    x: try #require(screen["x"] as? Double),
                    y: try #require(screen["y"] as? Double)
                ),
                size: Size(
                    width: try #require(screen["width"] as? Double),
                    height: try #require(screen["height"] as? Double)
                )
            )
        )
    }

    private static func imageSize(_ data: Data) throws -> Size {
        let source = try #require(
            CGImageSourceCreateWithData(data as CFData, nil)
        )
        let image = try #require(
            CGImageSourceCreateImageAtIndex(source, 0, nil)
        )
        return Size(
            width: Double(image.width),
            height: Double(image.height)
        )
    }
}
