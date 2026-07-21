import Foundation
import Testing
@testable import BaguetteCore

@Suite("DeviceRenderOptions")
struct DeviceRenderOptionsTests {

    @Test func `empty object uses HTTP render defaults`() throws {
        let options = try DeviceRenderOptions.parsing(json: Data("{}".utf8))

        #expect(options.rotation == .zero)
        #expect(options.variants == [:])
        #expect(options.size == nil)
        #expect(options.fit == .cover)
        #expect(options.background == .transparent)
        #expect(options.screenGlass == false)
    }

    @Test func `parses every HTTP render option`() throws {
        let options = try DeviceRenderOptions.parsing(json: Data("""
        {
          "rotation": {"x": -30, "y": 45, "z": 30},
          "variants": {"finish": "space-black"},
          "size": {"width": 1200, "height": 900},
          "fit": "contain",
          "background": "#112233",
          "screenGlass": true
        }
        """.utf8))

        #expect(options.rotation == DeviceRotation(x: -30, y: 45, z: 30))
        #expect(options.variants == ["finish": "space-black"])
        #expect(options.size == RenderDimensions(width: 1200, height: 900))
        #expect(options.fit == .contain)
        #expect(options.background == .color("#112233"))
        #expect(options.screenGlass == true)
    }

    @Test func `rejects malformed HTTP render options`() {
        #expect(throws: DeviceModelError.invalidRenderOptions) {
            _ = try DeviceRenderOptions.parsing(json: Data("""
            {"fit":"tile","size":{"width":0,"height":900}}
            """.utf8))
        }
    }
}
