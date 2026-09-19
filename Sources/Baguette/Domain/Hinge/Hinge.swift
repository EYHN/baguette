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

    /// Every sample the runtime reports, in order, until the watch is
    /// cancelled. Device Hub animates a pose change as a 0.5–0.85 s
    /// sweep at 60 Hz (0° closed, 130° its open pose, 180° flat), and
    /// this is how a page draws the fold at the angle the device is
    /// actually at. A device without a hinge delivers nothing.
    func watch(onAngle: @escaping @Sendable (HingeAngle) -> Void) -> any HingeWatch
}

/// A running watch on a hinge; `cancel` stops the samples.
@Mockable
protocol HingeWatch: Sendable {
    func cancel()
}
