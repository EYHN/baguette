import Foundation
import Testing
@testable import BaguetteCore

@Suite("Device chrome stand")
struct DeviceChromeStandTests {
    @Test func `parses the real Apple TV three-slice stand`() throws {
        let chrome = try DeviceChrome.parsing(json: Data(
            #"""
            {
              "identifier": "com.apple.dt.devicekit.chrome.tv",
              "images": {
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
        ))

        #expect(chrome.stand == DeviceChromeStand(
            width: 620,
            height: 26,
            left: "TvStand L",
            center: "TvStand",
            right: "TvStand R"
        ))
    }
}
