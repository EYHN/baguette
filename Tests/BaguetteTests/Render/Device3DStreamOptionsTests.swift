import Testing
@testable import BaguetteCore

@Suite("Device3DStreamOptions")
struct Device3DStreamOptionsTests {
    @Test func `empty query uses live stream defaults`() throws {
        let options = try Device3DStreamOptions.parse([:])

        #expect(options.rotation == DeviceRotation(x: -8, y: 18, z: 0))
        #expect(options.variants == [:])
        #expect(options.outputSize == RenderDimensions(width: 960, height: 960))
        #expect(options.fit == .cover)
        #expect(options.background == .color("#eef1f5"))
        #expect(options.screenGlass == false)
    }

    @Test func `parses camera output and repeatable public variants`() throws {
        let options = try Device3DStreamOptions.parse([
            "rotation": ["-12,24,3"],
            "variant": ["finish:deep-blue", "keyboard:ansi"],
            "width": ["1280"],
            "height": ["720"],
            "fit": ["contain"],
            "background": ["transparent"],
            "screenGlass": ["true"],
        ])

        #expect(options.rotation == DeviceRotation(x: -12, y: 24, z: 3))
        #expect(options.variants == [
            "finish": "deep-blue",
            "keyboard": "ansi",
        ])
        #expect(options.outputSize == RenderDimensions(width: 1280, height: 720))
        #expect(options.fit == .contain)
        #expect(options.background == .transparent)
        #expect(options.screenGlass == true)
    }

    @Test func `rejects a malformed screen glass flag`() {
        #expect(throws: DeviceModelError.invalidRenderOptions) {
            _ = try Device3DStreamOptions.parse(["screenGlass": ["shiny"]])
        }
    }

    @Test func `aligns live output dimensions for hardware video codecs`() throws {
        let options = try Device3DStreamOptions.parse([
            "width": ["669"],
            "height": ["1047"],
        ])

        #expect(options.outputSize == RenderDimensions(width: 670, height: 1048))
    }

    @Test func `rejects duplicate variant set selection`() {
        #expect(throws: DeviceModelError.duplicateVariantSelection("finish")) {
            _ = try Device3DStreamOptions.parse([
                "variant": ["finish:deep-blue", "finish:silver"],
            ])
        }
    }

    @Test func `rejects malformed connection options`() {
        #expect(throws: DeviceModelError.invalidRenderOptions) {
            _ = try Device3DStreamOptions.parse(["rotation": ["sideways"]])
        }
        #expect(throws: DeviceModelError.invalidRenderOptions) {
            _ = try Device3DStreamOptions.parse(["width": ["0"]])
        }
        #expect(throws: DeviceModelError.invalidRenderOptions) {
            _ = try Device3DStreamOptions.parse(["fit": ["squash"]])
        }
    }
}
