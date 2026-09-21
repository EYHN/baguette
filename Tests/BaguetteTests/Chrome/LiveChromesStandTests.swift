import Foundation
import Mockable
import Testing
@testable import BaguetteCore

@Suite("Live chrome stand")
struct LiveChromesStandTests {
    @Test func `Apple TV stand extends the viewport without extending the screen`() throws {
        let store = MockChromeStore()
        let rasterizer = MockPDFRasterizer()
        let body = ChromeImage(
            data: Data("TV-BODY".utf8),
            size: Size(width: 1_936, height: 1_096)
        )
        let stand = ChromeImage(
            data: Data("TV-STAND".utf8),
            size: Size(width: 620, height: 26)
        )
        let merged = ChromeImage(
            data: Data("TV-WITH-STAND".utf8),
            size: Size(width: 1_936, height: 1_122)
        )

        given(store).profilePlistData(deviceName: .value("Apple TV 4K"))
            .willReturn(Self.profile)
        given(store).capabilitiesPlistData(deviceName: .value("Apple TV 4K"))
            .willReturn(Self.capabilities)
        given(store).chromeJSONData(chromeIdentifier: .value("tv"))
            .willReturn(Self.chrome)
        for name in Self.bezelPDFNames {
            given(store).chromeAssetPDF(
                chromeIdentifier: .value("tv"),
                imageName: .value(name)
            ).willReturn(Data(name.utf8))
        }
        for name in Self.standPDFNames {
            given(store).chromeAssetPDF(
                chromeIdentifier: .value("tv"),
                imageName: .value(name)
            ).willReturn(Data(name.utf8))
        }
        given(rasterizer).compose9Slice(
            pdfs: .any,
            insets: .value(
                Insets(top: 8, left: 8, bottom: 8, right: 8)
            ),
            innerSize: .value(Size(width: 1_920, height: 1_080))
        ).willReturn(body)
        given(rasterizer).composeHorizontalSlice(
            pdfs: .any,
            size: .value(Size(width: 620, height: 26))
        ).willReturn(stand)
        given(rasterizer).compose(
            canvasSize: .value(Size(width: 1_936, height: 1_122)),
            layers: .matching { layers in
                layers == [
                    ImageLayer(
                        image: body,
                        topLeft: Point(x: 0, y: 0)
                    ),
                    ImageLayer(
                        image: stand,
                        topLeft: Point(x: 658, y: 1_096)
                    ),
                ]
            }
        ).willReturn(merged)

        let presentation = try LiveDevicePresentations(
            store: store,
            rasterizer: rasterizer
        ).presentation(forDeviceName: "Apple TV 4K")

        #expect(presentation.viewport == Size(width: 1_936, height: 1_122))
        #expect(presentation.screen == Rect(
            origin: Point(x: 8, y: 8),
            size: Size(width: 1_920, height: 1_080)
        ))
        #expect(presentation.bezelPNG == merged.data)
    }

    private static let bezelPDFNames = [
        "Tv TL", "Tv Top", "Tv TR", "Tv Right",
        "Tv BR", "Tv Bot", "Tv BL", "Tv Left",
    ]
    private static let standPDFNames = [
        "TvStand L", "TvStand", "TvStand R",
    ]

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
            "topLeft": "Tv TL",
            "top": "Tv Top",
            "topRight": "Tv TR",
            "right": "Tv Right",
            "bottomRight": "Tv BR",
            "bottom": "Tv Bot",
            "bottomLeft": "Tv BL",
            "left": "Tv Left",
            "screen": "Screen",
            "sizing": {
              "leftWidth": 8,
              "rightWidth": 8,
              "topHeight": 8,
              "bottomHeight": 8
            },
            "stand": {
              "width": 620,
              "height": 26,
              "left": "TvStand L",
              "center": "TvStand",
              "right": "TvStand R"
            }
          },
          "paths": {
            "simpleOutsideBorder": {
              "cornerRadiusX": 4,
              "cornerRadiusY": 4
            }
          },
          "inputs": []
        }
        """#.utf8
    )
}
