import Foundation

/// How a foldable's model is posed for a hinge angle.
///
/// The model's shutting clip raises the left half alone, from flat at
/// its start to shut at the fold's shut time. Device Hub's open poses are
/// a centred bend, so the whole device turns back by half the fold to
/// share it between the halves — fully above the open pose, handing
/// over as the book shuts so the cover ends facing the camera.
struct FoldPose: Equatable, Sendable {
    let clipTime: Double
    /// About the hinge axis, degrees; negative turns the raised left half
    /// back toward the camera's centre line.
    let yawDegrees: Double

    static func at(degrees: Double, fold: DeviceModelFold) -> FoldPose {
        let angle = max(0, min(180, degrees))
        let foldDegrees = 180 - angle
        let share = max(0, min(1, angle / fold.openPoseDegrees))
        return FoldPose(
            clipTime: foldDegrees / 180 * fold.shutTime,
            yawDegrees: -(foldDegrees / 2) * share
        )
    }
}
