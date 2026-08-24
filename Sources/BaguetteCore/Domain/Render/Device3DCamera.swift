import Foundation

struct Device3DCamera: Equatable, Sendable {
    let rotation: DeviceRotation
    let zoom: Double

    static func parsing(json: Data) throws -> Device3DCamera? {
        let object: [String: Any]
        do {
            object = try JSONSerialization.jsonObject(with: json) as? [String: Any] ?? [:]
        } catch {
            throw DeviceModelError.invalidRenderOptions
        }
        guard object["type"] as? String == "set_3d_camera" else { return nil }
        guard let rotation = object["rotation"] as? [String: Any],
              let x = number(rotation["x"]),
              let y = number(rotation["y"]),
              let z = number(rotation["z"]),
              let zoom = number(object["zoom"]),
              (-80...80).contains(x),
              (-180...180).contains(y),
              (-180...180).contains(z),
              (0.5...3).contains(zoom) else {
            throw DeviceModelError.invalidRenderOptions
        }
        return Device3DCamera(
            rotation: DeviceRotation(x: x, y: y, z: z),
            zoom: zoom
        )
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }
}
