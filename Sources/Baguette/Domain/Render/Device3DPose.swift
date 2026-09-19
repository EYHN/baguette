import Foundation

/// Device Hub's pose picker, on the page: `{"type":"set_pose","hingeDegrees":130}`
/// on the 3D socket, beside `set_3d_camera`, moves the device's hinge
/// there (`Hinge.fold`); the book follows the hinge as it sweeps.
enum Device3DPose: Equatable, Sendable {
    case fold(hingeDegrees: Double)

    static func parsing(json: Data) throws -> Device3DPose? {
        let object: [String: Any]
        do {
            object = try JSONSerialization.jsonObject(with: json) as? [String: Any] ?? [:]
        } catch {
            throw DeviceModelError.invalidRenderOptions
        }
        guard object["type"] as? String == "set_pose" else { return nil }
        let degrees: Double?
        if let d = object["hingeDegrees"] as? Double { degrees = d }
        else if let i = object["hingeDegrees"] as? Int { degrees = Double(i) }
        else { degrees = nil }
        guard let degrees, degrees.isFinite, (0...180).contains(degrees) else {
            throw DeviceModelError.invalidRenderOptions
        }
        return .fold(hingeDegrees: degrees)
    }
}

/// The pose a foldable's book is shown at: the hinge's own angle.
struct FoldablePose: Equatable, Sendable {
    let hingeDegrees: Double
}
