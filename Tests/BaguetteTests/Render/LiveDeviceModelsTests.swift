import Foundation
import Testing
@testable import BaguetteCore

@Suite("LiveDeviceModels")
struct LiveDeviceModelsTests {

    @Test func `discovers model bundles and preserves configured root precedence`() throws {
        let scratch = try Self.makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let overrideRoot = scratch.appending(path: "override")
        let bundledRoot = scratch.appending(path: "bundled")
        try Self.installModel(id: "phone", displayName: "Override", in: overrideRoot)
        try Self.installModel(id: "phone", displayName: "Bundled", in: bundledRoot)

        let models = try LiveDeviceModels(rootURLs: [overrideRoot, bundledRoot])
        let found = try #require(try models.find(id: "phone"))

        #expect(found.definition.displayName == "Override")
        #expect(found.directoryURL.lastPathComponent == "phone")
    }

    @Test func `ignores root entries that are not model bundles`() throws {
        let scratch = try Self.makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let root = scratch.appending(path: "models")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("notes".utf8).write(to: root.appending(path: "README.txt"))
        try FileManager.default.createDirectory(
            at: root.appending(path: "unfinished"),
            withIntermediateDirectories: true
        )
        try Self.installModel(id: "phone", displayName: "Phone", in: root)

        let models = try LiveDeviceModels(rootURLs: [root])

        #expect(try models.find(id: "phone") != nil)
        #expect(try models.find(id: "unfinished") == nil)
    }

    @Test func `missing configured roots are empty precedence layers`() throws {
        let scratch = try Self.makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let missing = scratch.appending(path: "not-installed")

        let models = try LiveDeviceModels(rootURLs: [missing])

        #expect(try models.find(id: "phone") == nil)
    }

    @Test func `reports the definition path when an installed bundle is malformed`() throws {
        let scratch = try Self.makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let root = scratch.appending(path: "models")
        let bundle = root.appending(path: "broken")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let definition = bundle.appending(path: "definition.json")
        try Data("{broken".utf8).write(to: definition)

        do {
            _ = try LiveDeviceModels(rootURLs: [root])
            Issue.record("expected malformed definition to fail discovery")
        } catch let DeviceModelError.malformedDefinition(path) {
            #expect(path.hasSuffix("/models/broken/definition.json"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}

private extension LiveDeviceModelsTests {
    static func makeScratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "baguette-models-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func installModel(
        id: String,
        displayName: String,
        in root: URL
    ) throws {
        let bundle = root.appending(path: id)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let json = """
        {
          "schemaVersion": 1,
          "id": "\(id)",
          "displayName": "\(displayName)",
          "matches": {
            "simulatorDeviceTypes": [],
            "deviceNames": ["iPhone 17 Pro"]
          },
          "asset": {"file": "device.usdz"},
          "scene": {
            "rootNode": "Device",
            "screenNode": "Screen",
            "screenMaterial": "Screen",
            "nativeOrientation": "portrait",
            "textureSize": {"width": 1179, "height": 2556},
            "usesScreenOverlay": false
          },
          "variantSets": []
        }
        """
        try Data(json.utf8).write(to: bundle.appending(path: "definition.json"))
    }
}
