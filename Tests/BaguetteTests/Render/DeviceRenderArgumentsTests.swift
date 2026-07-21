import Testing
@testable import BaguetteCore

@Suite("DeviceRenderArguments")
struct DeviceRenderArgumentsTests {

    @Test func `parses rotation size and repeatable variants`() throws {
        #expect(try DeviceRenderArguments.rotation("-30,45,30")
            == DeviceRotation(x: -30, y: 45, z: 30))
        #expect(try DeviceRenderArguments.size("1200x900")
            == RenderDimensions(width: 1200, height: 900))
        #expect(try DeviceRenderArguments.variants([
            "finish=space-black", "keyboard=iso"
        ]) == [
            "finish": "space-black",
            "keyboard": "iso"
        ])
    }

    @Test func `rejects malformed rotation`() {
        #expect(throws: DeviceModelError.invalidRotationArgument("20,10")) {
            _ = try DeviceRenderArguments.rotation("20,10")
        }
    }

    @Test func `rejects malformed size`() {
        #expect(throws: DeviceModelError.invalidSizeArgument("1200")) {
            _ = try DeviceRenderArguments.size("1200")
        }
    }

    @Test func `rejects duplicate variant selection`() {
        #expect(throws: DeviceModelError.duplicateVariantSelection("finish")) {
            _ = try DeviceRenderArguments.variants([
                "finish=black", "finish=silver"
            ])
        }
    }
}
