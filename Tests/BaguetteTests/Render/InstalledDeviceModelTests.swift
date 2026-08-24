import Foundation
import Testing
@testable import BaguetteCore

@Suite("InstalledDeviceModel")
struct InstalledDeviceModelTests {

    @Test func `local asset resolves relative to its model bundle`() throws {
        let scratch = try Self.makeBundle()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let asset = scratch.appending(path: "device.usdz")
        FileManager.default.createFile(atPath: asset.path, contents: Data())
        let model = Self.installed(directory: scratch, file: "device.usdz")

        #expect(try model.localAssetURL() == asset)
    }

    @Test func `local asset rejects parent traversal`() throws {
        let scratch = try Self.makeBundle()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = Self.installed(directory: scratch, file: "../secret.usdz")

        #expect(throws: DeviceModelError.assetOutsideBundle("../secret.usdz")) {
            _ = try model.localAssetURL()
        }
    }

    @Test func `local asset rejects a symlink that leaves its model bundle`() throws {
        let scratch = try Self.makeBundle()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let outside = scratch.deletingLastPathComponent()
            .appending(path: "outside-\(UUID().uuidString).usdz")
        defer { try? FileManager.default.removeItem(at: outside) }
        FileManager.default.createFile(atPath: outside.path, contents: Data())
        try FileManager.default.createSymbolicLink(
            at: scratch.appending(path: "device.usdz"),
            withDestinationURL: outside
        )
        let model = Self.installed(directory: scratch, file: "device.usdz")

        #expect(throws: DeviceModelError.assetOutsideBundle("device.usdz")) {
            _ = try model.localAssetURL()
        }
    }

    @Test func `local asset reports a missing file`() throws {
        let scratch = try Self.makeBundle()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = Self.installed(directory: scratch, file: "missing.usdz")

        #expect(throws: DeviceModelError.localAssetNotFound("missing.usdz")) {
            _ = try model.localAssetURL()
        }
    }
}

private extension InstalledDeviceModelTests {
    static func makeBundle() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "baguette-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func installed(directory: URL, file: String) -> InstalledDeviceModel {
        InstalledDeviceModel(
            definition: DeviceModelDefinition(
                schemaVersion: 1,
                id: "phone",
                displayName: "Phone",
                matches: DeviceModelMatches(),
                asset: DeviceModelAsset(file: file, downloadURL: nil, sha256: nil),
                scene: DeviceModelScene(
                    rootNode: "Device",
                    screenNode: "Screen",
                    screenMaterial: "Screen",
                    nativeOrientation: .portrait,
                    textureSize: RenderDimensions(width: 100, height: 200),
                    usesScreenOverlay: false
                ),
                variantSets: []
            ),
            directoryURL: directory
        )
    }
}
