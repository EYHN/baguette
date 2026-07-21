import Foundation

struct DeviceRenderOptions: Equatable, Sendable {
    let rotation: DeviceRotation
    let variants: [String: String]
    let size: RenderDimensions?
    let fit: DeviceScreenFit
    let background: DeviceRenderBackground
    let screenGlass: Bool

    static func parsing(json: Data) throws -> DeviceRenderOptions {
        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: json)
        } catch {
            throw DeviceModelError.invalidRenderOptions
        }

        let rotation = DeviceRotation(
            x: wire.rotation?.x ?? 0,
            y: wire.rotation?.y ?? 0,
            z: wire.rotation?.z ?? 0
        )
        guard rotation.x.isFinite, rotation.y.isFinite, rotation.z.isFinite else {
            throw DeviceModelError.invalidRenderOptions
        }

        let size = wire.size.map {
            RenderDimensions(width: $0.width, height: $0.height)
        }
        if let size, size.width <= 0 || size.height <= 0 {
            throw DeviceModelError.invalidRenderOptions
        }
        guard let fit = DeviceScreenFit(rawValue: wire.fit ?? "cover") else {
            throw DeviceModelError.invalidRenderOptions
        }

        let background: DeviceRenderBackground
        let backgroundValue = wire.background ?? "transparent"
        if backgroundValue == "transparent" {
            background = .transparent
        } else {
            let pattern = #"^#[0-9A-Fa-f]{6}$"#
            guard backgroundValue.range(
                of: pattern,
                options: .regularExpression
            ) != nil else {
                throw DeviceModelError.invalidRenderOptions
            }
            background = .color(backgroundValue)
        }

        return DeviceRenderOptions(
            rotation: rotation,
            variants: wire.variants ?? [:],
            size: size,
            fit: fit,
            background: background,
            screenGlass: wire.screenGlass ?? false
        )
    }
}

private extension DeviceRenderOptions {
    struct Wire: Decodable {
        let rotation: Rotation?
        let variants: [String: String]?
        let size: Size?
        let fit: String?
        let background: String?
        let screenGlass: Bool?
    }

    struct Rotation: Decodable {
        let x: Double
        let y: Double
        let z: Double
    }

    struct Size: Decodable {
        let width: Int
        let height: Int
    }
}
