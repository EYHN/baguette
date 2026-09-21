import Foundation
import CoreGraphics

/// Projects a `CGRect` reported by `AXPTranslator` (in macOS
/// host-window coordinates — where the simulator's window would
/// land on the host's screen) into device-point coordinates,
/// matching the units the gesture wire uses (`tap.x`, `tap.y`,
/// `width`, `height`).
///
/// The math is width-uniform scale + vertical centering offset,
/// which is exactly what Simulator.app does when a tall device
/// has to letterbox into a short window. Falls back to identity
/// when either the AX root frame or the device point-size has a
/// zero dimension — that's how we avoid dividing by zero on a
/// just-booted simulator that hasn't reported its bounds yet.
struct AXFrameTransform: Equatable, Sendable {
    let rootFrame: CGRect
    let pointSize: CGSize
    var orientation: ScreenOrientation = .portrait
    /// The root exactly as AXP reported it, when `presenting` restated it.
    var reportedRoot: CGRect? = nil

    /// The transform for a UI presented in `orientation`. AXP normally
    /// reports a landscape UI's root in landscape; on a panel mounted
    /// sideways (iPhone Duo's inner display) it reports the elements in
    /// the upright frame but the root as the panel's own portrait
    /// rectangle. Read against that root every element would be scaled
    /// by the wrong axis, so a root whose shape contradicts the UI's is
    /// restated as the upright frame it actually describes.
    static func presenting(
        rootFrame: CGRect, pointSize: CGSize, orientation: ScreenOrientation
    ) -> AXFrameTransform {
        let landscapeUI = orientation == .landscapeRight || orientation == .landscapeLeft
        let contradicts = landscapeUI && rootFrame.width < rootFrame.height
        let root = contradicts
            ? CGRect(x: rootFrame.origin.x, y: rootFrame.origin.y,
                     width: rootFrame.height, height: rootFrame.width)
            : rootFrame
        return AXFrameTransform(
            rootFrame: root, pointSize: pointSize, orientation: orientation,
            reportedRoot: contradicts ? rootFrame : nil
        )
    }

    private var logicalSize: CGSize {
        switch orientation {
        case .landscapeRight, .landscapeLeft:
            return CGSize(width: pointSize.height, height: pointSize.width)
        default: return pointSize
        }
    }

    private func physical(_ p: CGPoint) -> CGPoint {
        switch orientation {
        case .portrait: return p
        case .portraitUpsideDown: return CGPoint(x: pointSize.width - p.x, y: pointSize.height - p.y)
        case .landscapeRight: return CGPoint(x: p.y, y: pointSize.height - p.x)
        case .landscapeLeft: return CGPoint(x: pointSize.width - p.y, y: p.x)
        }
    }

    func map(_ macFrame: CGRect) -> CGRect {
        guard rootFrame.width > 0,
              rootFrame.height > 0,
              pointSize.width > 0,
              pointSize.height > 0
        else { return macFrame }
        // The root is the one frame AXP reports in the panel's own shape
        // rather than the upright UI's; it is the whole panel.
        if macFrame == reportedRoot { return CGRect(origin: .zero, size: pointSize) }

        let scale = logicalSize.width / rootFrame.width
        let yOffset = (logicalSize.height - rootFrame.height * scale) / 2
        let logical = CGRect(
            x: (macFrame.origin.x - rootFrame.origin.x) * scale,
            y: (macFrame.origin.y - rootFrame.origin.y) * scale + yOffset,
            width: macFrame.size.width * scale,
            height: macFrame.size.height * scale
        )
        let a = physical(logical.origin)
        let b = physical(CGPoint(x: logical.maxX, y: logical.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// Inverse of `map(_:)`: takes a device-point coordinate (the
    /// units callers pass into the gesture wire) and projects it
    /// back to macOS host-window coordinates. Needed when feeding
    /// AXP APIs that work in host coordinates — most notably
    /// `objectAtPoint:displayId:bridgeDelegateToken:`, where the
    /// translator interprets the point in its own host coordinate
    /// space, not in device points. Falls back to identity under
    /// the same zero-dimension conditions as `map(_:)`.
    func unmap(_ devicePoint: CGPoint) -> CGPoint {
        guard rootFrame.width > 0,
              rootFrame.height > 0,
              pointSize.width > 0,
              pointSize.height > 0
        else { return devicePoint }

        let logical: CGPoint
        switch orientation {
        case .portrait: logical = devicePoint
        case .portraitUpsideDown:
            logical = CGPoint(x: pointSize.width - devicePoint.x, y: pointSize.height - devicePoint.y)
        case .landscapeRight:
            logical = CGPoint(x: pointSize.height - devicePoint.y, y: devicePoint.x)
        case .landscapeLeft:
            logical = CGPoint(x: devicePoint.y, y: pointSize.width - devicePoint.x)
        }
        let scale = logicalSize.width / rootFrame.width
        let yOffset = (logicalSize.height - rootFrame.height * scale) / 2
        return CGPoint(
            x: logical.x / scale + rootFrame.origin.x,
            y: (logical.y - yOffset) / scale + rootFrame.origin.y
        )
    }
}
