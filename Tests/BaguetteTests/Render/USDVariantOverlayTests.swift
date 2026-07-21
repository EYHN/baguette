import Testing
@testable import BaguetteCore

@Suite("USDVariantOverlay")
struct USDVariantOverlayTests {

    @Test func `authors root variant selections over a sublayer`() throws {
        let source = try USDVariantOverlay.make(
            assetReference: "device.usdz",
            selections: [
                DeviceVariantSelection(
                    setID: "finish",
                    primPath: "/Device",
                    usdName: "Color",
                    usdValue: "Space_Black"
                )
            ]
        )

        #expect(source == """
        #usda 1.0
        (
            subLayers = [@device.usdz@]
        )

        over "Device" (
            variants = {
                string Color = "Space_Black"
            }
        )
        {
        }

        """)
    }

    @Test func `authors independent selections on the same prim`() throws {
        let source = try USDVariantOverlay.make(
            assetReference: "device.usdz",
            selections: [
                DeviceVariantSelection(
                    setID: "finish",
                    primPath: "/Device",
                    usdName: "Color",
                    usdValue: "Silver"
                ),
                DeviceVariantSelection(
                    setID: "keyboard",
                    primPath: "/Device",
                    usdName: "Keyboard",
                    usdValue: "ISO"
                )
            ]
        )

        #expect(source.contains(#"string Color = "Silver""#))
        #expect(source.contains(#"string Keyboard = "ISO""#))
        #expect(source.components(separatedBy: #"over "Device""#).count == 2)
    }

    @Test func `authors a selection on a nested prim path`() throws {
        let source = try USDVariantOverlay.make(
            assetReference: "device.usdz",
            selections: [
                DeviceVariantSelection(
                    setID: "stand",
                    primPath: "/Device/Stand",
                    usdName: "Position",
                    usdValue: "Raised"
                )
            ]
        )

        #expect(source.contains("""
        over "Device"
        {
            over "Stand" (
        """))
        #expect(source.contains(#"string Position = "Raised""#))
    }

    @Test func `rejects unsafe USD identifiers before authoring`() {
        #expect(throws: DeviceModelError.invalidUSDIdentifier("Bad Name")) {
            _ = try USDVariantOverlay.make(
                assetReference: "device.usdz",
                selections: [
                    DeviceVariantSelection(
                        setID: "finish",
                        primPath: "/Bad Name",
                        usdName: "Color",
                        usdValue: "Silver"
                    )
                ]
            )
        }
    }
}
