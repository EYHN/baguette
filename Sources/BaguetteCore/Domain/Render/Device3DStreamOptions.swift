import Foundation

/// Public connection options for a live 3D stream.
///
/// Infrastructure projects the URI query into `[String: [String]]`; keeping
/// parsing here avoids coupling render semantics to Hummingbird.
struct Device3DStreamOptions: Equatable, Sendable {
    let rotation: DeviceRotation
    let variants: [String: String]
    let outputSize: RenderDimensions
    let fit: DeviceScreenFit
    let background: DeviceRenderBackground
    let screenGlass: Bool

    static let `default` = Device3DStreamOptions(
        rotation: DeviceRotation(x: -8, y: 18, z: 0),
        variants: [:],
        outputSize: RenderDimensions(width: 960, height: 960),
        fit: .cover,
        background: .color("#eef1f5"),
        screenGlass: false
    )

    static func parse(_ query: [String: [String]]) throws -> Device3DStreamOptions {
        let rotation = try query.single("rotation").map(parseRotation)
            ?? Self.default.rotation
        let width = try query.single("width").map(parsePositiveInt)
            ?? Self.default.outputSize.width
        let height = try query.single("height").map(parsePositiveInt)
            ?? Self.default.outputSize.height
        let fit = try query.single("fit").map { value in
            guard let fit = DeviceScreenFit(rawValue: value) else {
                throw DeviceModelError.invalidRenderOptions
            }
            return fit
        } ?? Self.default.fit
        let background = try query.single("background").map(parseBackground)
            ?? Self.default.background
        let screenGlass = try query.single("screenGlass").map(parseBool)
            ?? Self.default.screenGlass

        var variants: [String: String] = [:]
        for value in query["variant"] ?? [] {
            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  !parts[0].isEmpty,
                  !parts[1].isEmpty else {
                throw DeviceModelError.invalidRenderOptions
            }
            guard variants.updateValue(parts[1], forKey: parts[0]) == nil else {
                throw DeviceModelError.duplicateVariantSelection(parts[0])
            }
        }

        return Device3DStreamOptions(
            rotation: rotation,
            variants: variants,
            outputSize: VideoFrameDimensions(
                requested: RenderDimensions(width: width, height: height)
            ).renderDimensions,
            fit: fit,
            background: background,
            screenGlass: screenGlass
        )
    }

    private static func parseRotation(_ value: String) throws -> DeviceRotation {
        let values = value.split(separator: ",").compactMap { Double($0) }
        guard values.count == 3, values.allSatisfy(\.isFinite) else {
            throw DeviceModelError.invalidRenderOptions
        }
        return DeviceRotation(x: values[0], y: values[1], z: values[2])
    }

    private static func parsePositiveInt(_ value: String) throws -> Int {
        guard let result = Int(value), result > 0, result <= 4096 else {
            throw DeviceModelError.invalidRenderOptions
        }
        return result
    }

    private static func parseBool(_ value: String) throws -> Bool {
        switch value {
        case "true": return true
        case "false": return false
        default: throw DeviceModelError.invalidRenderOptions
        }
    }

    private static func parseBackground(_ value: String) throws -> DeviceRenderBackground {
        if value == "transparent" { return .transparent }
        guard value.range(
            of: #"^#[0-9A-Fa-f]{6}$"#,
            options: .regularExpression
        ) != nil else {
            throw DeviceModelError.invalidRenderOptions
        }
        return .color(value)
    }
}

private extension Dictionary where Key == String, Value == [String] {
    func single(_ key: String) throws -> String? {
        guard let values = self[key] else { return nil }
        guard values.count == 1 else {
            throw DeviceModelError.invalidRenderOptions
        }
        return values[0]
    }
}
