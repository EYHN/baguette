import Foundation

enum DeviceRenderArguments {
    static func rotation(_ value: String) throws -> DeviceRotation {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let x = Double(parts[0]),
              let y = Double(parts[1]),
              let z = Double(parts[2]),
              x.isFinite, y.isFinite, z.isFinite else {
            throw DeviceModelError.invalidRotationArgument(value)
        }
        return DeviceRotation(x: x, y: y, z: z)
    }

    static func size(_ value: String) throws -> RenderDimensions {
        let parts = value.lowercased()
            .split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]),
              width > 0, height > 0 else {
            throw DeviceModelError.invalidSizeArgument(value)
        }
        return RenderDimensions(width: width, height: height)
    }

    static func variants(_ values: [String]) throws -> [String: String] {
        var result: [String: String] = [:]
        for value in values {
            let parts = value.split(
                separator: "=",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                throw DeviceModelError.invalidVariantArgument(value)
            }
            let set = String(parts[0])
            guard result[set] == nil else {
                throw DeviceModelError.duplicateVariantSelection(set)
            }
            result[set] = String(parts[1])
        }
        return result
    }
}
