import Foundation
import Mockable

/// A simulator's hinge — the fold of iPhone Duo.
///
/// The angle is the runtime's own reading (see `HingeAngle`), and it
/// decides which of a foldable's panels is lit, so the phone plane binds
/// its framebuffer and digitizer through it. Single-panel devices have
/// no hinge and never ask.
///
/// Read-only for now: Device Hub drives the hinge through CoreDevice's
/// UniversalHID, a path baguette follows rather than speaks. The
/// production impl is `DevicectlHinge`.
@Mockable
protocol Hinge: Sendable {
    /// The current angle, or `nil` when the device has no hinge or the
    /// reading did not arrive. Callers take `nil` as "as booted": folded.
    func angle() -> HingeAngle?
}
