import AppKit
import Foundation
import ImageIO
import IOSurface

/// One-shot PNG renderer sharing the live RealityKit stage, so still
/// exports and the live stream produce identical colors and framing.
struct RealityKitDeviceRenderer: DeviceRenderer, Sendable {
    private let assets: VerifiedDeviceAssets

    init(assets: VerifiedDeviceAssets = VerifiedDeviceAssets()) {
        self.assets = assets
    }

    func render(plan: DeviceRenderPlan, screenImage: Data) throws -> Data {
        let scene = try RealityKitDeviceScene(plan: plan, assets: assets)
        guard let source = CGImageSourceCreateWithData(screenImage as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let surface = Self.surface(from: image) else {
            throw DeviceModelError.screenImageInvalid
        }
        let rendered = try scene.render(screen: surface)
        return try Self.png(from: rendered)
    }

    private static func surface(from image: CGImage) -> IOSurface? {
        let width = image.width
        let height = image.height
        let bytesPerRow = ((width * 4 + 63) / 64) * 64
        guard let surface = IOSurfaceCreate([
            kIOSurfaceWidth: width,
            kIOSurfaceHeight: height,
            kIOSurfaceBytesPerElement: 4,
            kIOSurfaceBytesPerRow: bytesPerRow,
            kIOSurfaceAllocSize: bytesPerRow * height,
            kIOSurfacePixelFormat: UInt32(0x42475241),
        ] as CFDictionary) else { return nil }
        IOSurfaceLock(surface, [], nil)
        defer { IOSurfaceUnlock(surface, [], nil) }
        guard let context = CGContext(
            data: IOSurfaceGetBaseAddress(surface),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: IOSurfaceGetBytesPerRow(surface),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return surface
    }

    private static func png(from surface: IOSurface) throws -> Data {
        IOSurfaceLock(surface, .readOnly, nil)
        defer { IOSurfaceUnlock(surface, .readOnly, nil) }
        guard let context = CGContext(
            data: IOSurfaceGetBaseAddress(surface),
            width: IOSurfaceGetWidth(surface),
            height: IOSurfaceGetHeight(surface),
            bitsPerComponent: 8,
            bytesPerRow: IOSurfaceGetBytesPerRow(surface),
            space: CGColorSpace(name: CGColorSpace.sRGB)
                ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ), let image = context.makeImage() else {
            throw DeviceModelError.renderFailed
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, "public.png" as CFString, 1, nil
        ) else {
            throw DeviceModelError.renderFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DeviceModelError.renderFailed
        }
        return output as Data
    }
}
