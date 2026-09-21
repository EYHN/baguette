import Foundation
import Mockable
import Testing
@testable import BaguetteCore

@Suite("Simulator 3D model")
struct SimulatorDeviceModelTests {

    @Test func `resolves a model from stable device type and visible name`() throws {
        let simulator = MockSimulator()
        let models = MockDeviceModels()
        let installed = Self.installed()
        given(simulator).deviceTypeName.willReturn("iPhone 17 Pro")
        given(simulator).name.willReturn("Demo Phone")
        given(models).match(
            deviceType: .value("iPhone 17 Pro"),
            deviceName: .value("Demo Phone")
        ).willReturn(installed)

        let found = try simulator.deviceModel(in: models)

        #expect(found == installed)
        verify(models).match(
            deviceType: .value("iPhone 17 Pro"),
            deviceName: .value("Demo Phone")
        ).called(1)
    }
}

private extension SimulatorDeviceModelTests {
    static func installed() -> InstalledDeviceModel {
        InstalledDeviceModel(
            definition: DeviceModelDefinition(
                schemaVersion: 1,
                id: "iphone-17-pro",
                displayName: "iPhone 17 Pro",
                matches: DeviceModelMatches(),
                asset: DeviceModelAsset(file: "device.usdz", downloadURL: nil, sha256: nil),
                scene: DeviceModelScene(
                    rootNode: "Device",
                    screenNode: "Screen",
                    screenMaterial: "Screen",
                    nativeOrientation: .portrait,
                    textureSize: RenderDimensions(width: 1179, height: 2556),
                    usesScreenOverlay: false
                ),
                variantSets: []
            ),
            directoryURL: URL(fileURLWithPath: "/models/iphone")
        )
    }
}
