import Foundation
import Mockable
import Testing
@testable import BaguetteCore

@Suite("Live device presentations")
struct LiveDevicePresentationsTests {
    @Test func `uses DeviceKit tv chrome when the profile has no identifier`() throws {
        let store = MockChromeStore()
        let rasterizer = MockPDFRasterizer()
        let bezel = ChromeImage(
            data: Data("TV-PNG".utf8),
            size: Size(width: 1_936, height: 1_096)
        )

        given(store).profilePlistData(deviceName: .value("Apple TV 4K"))
            .willReturn(Self.profile)
        given(store).capabilitiesPlistData(deviceName: .value("Apple TV 4K"))
            .willReturn(Self.capabilities)
        given(store).chromeJSONData(chromeIdentifier: .value("tv"))
            .willReturn(Self.chrome)
        given(store).chromeAssetPDF(
            chromeIdentifier: .value("tv"),
            imageName: .value("TVComposite")
        ).willReturn(Data("TV-PDF".utf8))
        given(rasterizer).rasterize(pdfData: .value(Data("TV-PDF".utf8)))
            .willReturn(bezel)

        let presentation = try LiveDevicePresentations(
            store: store,
            rasterizer: rasterizer
        ).presentation(forDeviceName: "Apple TV 4K")

        #expect(presentation.style == .bezel)
        #expect(presentation.identifier == "tv")
        #expect(presentation.bezelPNG == bezel.data)
        #expect(presentation.screen.size == Size(width: 1_920, height: 1_080))
    }

    @Test func `keeps TV frameless when the optional system chrome is absent`() throws {
        let store = MockChromeStore()
        let rasterizer = MockPDFRasterizer()
        given(store).profilePlistData(deviceName: .value("Apple TV 4K"))
            .willReturn(Self.profile)
        given(store).capabilitiesPlistData(deviceName: .value("Apple TV 4K"))
            .willReturn(Self.capabilities)
        given(store).chromeJSONData(chromeIdentifier: .value("tv"))
            .willThrow(FixtureError.notFound)

        let presentation = try LiveDevicePresentations(
            store: store,
            rasterizer: rasterizer
        ).presentation(forDeviceName: "Apple TV 4K")

        #expect(presentation.style == .frameless)
        #expect(presentation.formFactor == .tv)
        #expect(presentation.viewport == Size(width: 1_920, height: 1_080))
        #expect(presentation.bezelPNG == nil)
    }

    private static let profile = try! PropertyListSerialization.data(
        fromPropertyList: [:],
        format: .xml,
        options: 0
    )

    private static let capabilities = try! PropertyListSerialization.data(
        fromPropertyList: [
            "capabilities": [
                "idiom": "tv",
                "displays": [[
                    "displayType": "tvOut",
                    "width": 3_840,
                    "height": 2_160,
                    "scale": 2,
                ]],
            ],
        ],
        format: .xml,
        options: 0
    )

    private static let chrome = Data(
        #"""
        {
          "identifier": "com.apple.dt.devicekit.chrome.tv",
          "images": {
            "composite": "TVComposite",
            "sizing": {
              "leftWidth": 8,
              "rightWidth": 8,
              "topHeight": 8,
              "bottomHeight": 8
            }
          },
          "paths": {
            "simpleOutsideBorder": {
              "cornerRadiusX": 10,
              "cornerRadiusY": 10
            }
          },
          "inputs": []
        }
        """#.utf8
    )
}

private enum FixtureError: Error {
    case notFound
}
