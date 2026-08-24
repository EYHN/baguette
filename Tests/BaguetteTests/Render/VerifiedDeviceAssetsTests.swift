import CryptoKit
import Foundation
import Testing
@testable import BaguetteCore

@Suite("VerifiedDeviceAssets")
struct VerifiedDeviceAssetsTests {

    @Test func `existing local asset wins without downloading`() throws {
        let scratch = try Self.makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let bundle = scratch.appending(path: "bundle")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let local = bundle.appending(path: "device.usdz")
        try Data("LOCAL".utf8).write(to: local)
        let model = Self.model(directory: bundle, file: "device.usdz")
        var downloads = 0
        let assets = VerifiedDeviceAssets(
            cacheRoot: scratch.appending(path: "cache"),
            fetch: { _ in downloads += 1; return Data("REMOTE".utf8) }
        )

        #expect(try assets.resolve(model) == local)
        #expect(downloads == 0)
    }

    @Test func `verified download is atomically cached`() throws {
        let scratch = try Self.makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let bytes = Data("VERIFIED-USDZ".utf8)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let model = Self.model(
            directory: scratch.appending(path: "bundle"),
            file: "device.usdz",
            downloadURL: "https://example.com/device.usdz",
            sha256: hash
        )
        var downloads = 0
        let assets = VerifiedDeviceAssets(
            cacheRoot: scratch.appending(path: "cache"),
            fetch: { _ in downloads += 1; return bytes }
        )

        let resolved = try assets.resolve(model)

        #expect(try Data(contentsOf: resolved) == bytes)
        #expect(downloads == 1)
        #expect(try assets.resolve(model) == resolved)
        #expect(downloads == 1)
    }

    @Test func `hash mismatch never installs downloaded bytes`() throws {
        let scratch = try Self.makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let expected = String(repeating: "0", count: 64)
        let model = Self.model(
            directory: scratch.appending(path: "bundle"),
            file: nil,
            downloadURL: "https://example.com/device.usdz",
            sha256: expected
        )
        let assets = VerifiedDeviceAssets(
            cacheRoot: scratch.appending(path: "cache"),
            fetch: { _ in Data("TAMPERED".utf8) }
        )

        #expect(throws: DeviceModelError.assetHashMismatch) {
            _ = try assets.resolve(model)
        }
        #expect(FileManager.default.fileExists(
            atPath: scratch.appending(path: "cache/test-device/device.usdz").path
        ) == false)
    }
}

private extension VerifiedDeviceAssetsTests {
    static func makeScratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "baguette-assets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func model(
        directory: URL,
        file: String?,
        downloadURL: String? = nil,
        sha256: String? = nil
    ) -> InstalledDeviceModel {
        InstalledDeviceModel(
            definition: DeviceModelDefinition(
                schemaVersion: 1,
                id: "test-device",
                displayName: "Test",
                matches: DeviceModelMatches(),
                asset: DeviceModelAsset(
                    file: file,
                    downloadURL: downloadURL,
                    sha256: sha256
                ),
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
