import AppKit
import Foundation
import ImageIO
import Testing

@testable import BaguetteCore

@Suite("RealityKitDeviceRenderer")
struct RealityKitDeviceRendererTests {
    @Test func `renders a generated device scene to requested PNG dimensions`() throws {
        let scratch = try Self.makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let plan = try Self.plan(directory: scratch, file: "device.usda")
        let screen = try Self.screenPNG()

        let png = try RealityKitDeviceRenderer().render(plan: plan, screenImage: screen)

        #expect(Array(png.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 320)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 240)
        #expect(try Self.opaqueHeight(png) > 160)
    }

    @Test func `reports the declared local asset when it is missing`() throws {
        let scratch = try Self.makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let plan = try Self.plan(directory: scratch, file: "missing.usdz")

        #expect(throws: DeviceModelError.localAssetNotFound("missing.usdz")) {
            _ = try RealityKitDeviceRenderer().render(
                plan: plan,
                screenImage: Data("not reached".utf8)
            )
        }
    }

    @Test func `material appearance variant changes rendered device finish`() throws {
        let scratch = try Self.makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let orange = try Self.plan(
            directory: scratch, file: "device.usda", finish: "orange"
        )
        let blue = try Self.plan(
            directory: scratch, file: "device.usda", finish: "blue"
        )
        let screen = try Self.screenPNG()

        let orangePNG = try RealityKitDeviceRenderer().render(
            plan: orange, screenImage: screen
        )
        let bluePNG = try RealityKitDeviceRenderer().render(
            plan: blue, screenImage: screen
        )

        #expect(orangePNG != bluePNG)
    }
}

private extension RealityKitDeviceRendererTests {
    static func makeScratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "baguette-rk-render-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try RealityKitRenderFixtures.deviceUSDA.write(
            to: url.appending(path: "device.usda"),
            atomically: true,
            encoding: .utf8
        )
        return url
    }

    static func screenPNG() throws -> Data {
        let image = NSImage(size: NSSize(width: 100, height: 200))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 100, height: 200)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return png
    }

    static func opaqueHeight(_ png: Data) throws -> Int {
        let imageSource = try #require(
            CGImageSourceCreateWithData(png as CFData, nil)
        )
        let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let occupiedRows = (0..<height).filter { row in
            (0..<width).contains { column in
                pixels[(row * width + column) * 4 + 3] > 8
            }
        }
        guard let first = occupiedRows.first, let last = occupiedRows.last else {
            return 0
        }
        return last - first + 1
    }

    static func plan(
        directory: URL,
        file: String,
        finish: String? = nil
    ) throws -> DeviceRenderPlan {
        let model = InstalledDeviceModel(
            definition: DeviceModelDefinition(
                schemaVersion: 1,
                id: "test-device",
                displayName: "Test Device",
                matches: DeviceModelMatches(),
                asset: DeviceModelAsset(file: file, downloadURL: nil, sha256: nil),
                scene: DeviceModelScene(
                    rootNode: "Device",
                    screenNode: "Screen",
                    screenMaterial: "ScreenMaterial",
                    nativeOrientation: .portrait,
                    textureSize: RenderDimensions(width: 100, height: 200),
                    usesScreenOverlay: false
                ),
                variantSets: finish == nil ? [] : [
                    DeviceVariantSet(
                        id: "finish",
                        displayName: "Finish",
                        primPath: "/Device",
                        usdName: "Finish",
                        default: "orange",
                        choices: [
                            DeviceVariantChoice(
                                id: "orange",
                                displayName: "Orange",
                                usdValue: "Orange",
                                previewColor: "#ff6600",
                                materialColors: ["DeviceBody": "#ff6600"]
                            ),
                            DeviceVariantChoice(
                                id: "blue",
                                displayName: "Blue",
                                usdValue: "Blue",
                                previewColor: "#334477",
                                materialColors: ["DeviceBody": "#334477"]
                            ),
                        ],
                        kind: .materials
                    ),
                ]
            ),
            directoryURL: directory
        )
        return try DeviceRenderPlan.build(
            model: model,
            variants: finish.map { ["finish": $0] } ?? [:],
            rotation: DeviceRotation(x: -8, y: 18, z: 0),
            outputSize: RenderDimensions(width: 320, height: 240)
        )
    }
}
