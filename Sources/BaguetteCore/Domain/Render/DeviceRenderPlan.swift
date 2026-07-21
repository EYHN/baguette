import Foundation

struct DeviceRotation: Equatable, Sendable, Codable {
    let x: Double
    let y: Double
    let z: Double

    static let zero = DeviceRotation(x: 0, y: 0, z: 0)
}

enum DeviceScreenFit: String, Equatable, Sendable, Codable {
    case cover
    case contain
    case stretch
}

enum DeviceRenderBackground: Equatable, Sendable {
    case transparent
    case color(String)
}

struct DeviceRenderPlan: Equatable, Sendable {
    let model: InstalledDeviceModel
    let variants: [DeviceVariantSelection]
    let rotation: DeviceRotation
    let outputSize: RenderDimensions
    let fit: DeviceScreenFit
    let background: DeviceRenderBackground
    /// Composite a reflective cover-glass layer over the screen. Off by
    /// default so automation screenshots stay pixel-stable.
    let screenGlass: Bool

    static func build(
        model: InstalledDeviceModel,
        variants: [String: String],
        rotation: DeviceRotation,
        outputSize: RenderDimensions,
        fit: DeviceScreenFit = .cover,
        background: DeviceRenderBackground = .transparent,
        screenGlass: Bool = false
    ) throws -> DeviceRenderPlan {
        guard outputSize.width > 0, outputSize.height > 0 else {
            throw DeviceModelError.invalidOutputSize
        }
        guard rotation.x.isFinite, rotation.y.isFinite, rotation.z.isFinite else {
            throw DeviceModelError.invalidRotation
        }
        if case .color(let color) = background {
            let pattern = #"^#[0-9A-Fa-f]{6}$"#
            guard color.range(of: pattern, options: .regularExpression) != nil else {
                throw DeviceModelError.invalidBackground(color)
            }
        }
        return DeviceRenderPlan(
            model: model,
            variants: try model.definition.resolveVariants(variants),
            rotation: rotation,
            outputSize: outputSize,
            fit: fit,
            background: background,
            screenGlass: screenGlass
        )
    }
}
