import CoreGraphics
import Foundation

/// Converts UIKit screen points to the panel's native HID point space.
/// The bridge delegate leaves guest frames unchanged; application bounds
/// are neither host-window bounds nor a source of screen scale.
struct AXFrameTransform: Equatable, Sendable {
    let pointSize: CGSize
    let orientation: DeviceOrientation
    /// The application root exactly as AXP reported it, when it came in
    /// the panel's own portrait shape under a landscape UI; see
    /// `presenting(rootFrame:pointSize:orientation:)`.
    var panelShapedRoot: CGRect? = nil
    /// The application root as AXP reported it, when the application
    /// answers in the panel's native points already and nothing is to be
    /// turned; see `presenting(rootFrame:pointSize:orientation:)`.
    var nativeRoot: CGRect? = nil

    /// The transform for an application whose root AXP reported as
    /// `rootFrame`. On a panel mounted sideways (iPhone Duo's inner
    /// display) a landscape UI's elements arrive in the upright frame but
    /// the root arrives as the panel's portrait rectangle; rotated like
    /// an element it would leave the panel. That root is the whole panel.
    static func presenting(
        rootFrame: CGRect, pointSize: CGSize, orientation: DeviceOrientation
    ) -> AXFrameTransform {
        let landscapeUI = orientation == .landscapeLeft || orientation == .landscapeRight
        let panelShaped = landscapeUI && rootFrame.width < rootFrame.height
            && abs(rootFrame.width - pointSize.width) < 1 && abs(rootFrame.height - pointSize.height) < 1
        // SpringBoard on that panel (measured on iPhone Duo, iOS 27.2,
        // unfolded on the Home Screen) is a third case: its root is the
        // *cover's* portrait rectangle (466 × 678 inside the 669 × 951
        // panel) and its elements are already in the panel's native
        // points. Turned like an app's they land off the panel, and a tap
        // by label misses.
        let native = landscapeUI && !panelShaped && rootFrame.origin == .zero
            && rootFrame.width > 0 && rootFrame.width < rootFrame.height
            && rootFrame.width < pointSize.width - 1 && rootFrame.height < pointSize.height - 1
        return AXFrameTransform(
            pointSize: pointSize, orientation: orientation,
            panelShapedRoot: panelShaped ? rootFrame : nil,
            nativeRoot: native ? rootFrame : nil
        )
    }

    func map(_ frame: CGRect) -> CGRect {
        if let panelShapedRoot, frame == panelShapedRoot {
            return CGRect(origin: .zero, size: pointSize)
        }
        if let nativeRoot {
            return frame == nativeRoot ? CGRect(origin: .zero, size: pointSize) : frame
        }
        return turned(frame)
    }

    /// `frame` in UIKit's upright points, turned into the panel's.
    private func turned(_ frame: CGRect) -> CGRect {
        switch orientation {
        case .portrait:
            return frame
        case .portraitUpsideDown:
            return CGRect(
                x: pointSize.width - frame.maxX, y: pointSize.height - frame.maxY,
                width: frame.width, height: frame.height
            )
        case .landscapeLeft:
            return CGRect(
                x: frame.minY, y: pointSize.height - frame.maxX,
                width: frame.height, height: frame.width
            )
        case .landscapeRight:
            return CGRect(
                x: pointSize.width - frame.maxY, y: frame.minX,
                width: frame.height, height: frame.width
            )
        }
    }

    /// The strip along the top of the interface, where the status bar
    /// lives, in native panel points. UIKit's width is the panel's height
    /// once the interface is rotated sideways.
    func topStrip(height: CGFloat) -> CGRect {
        let sideways = orientation == .landscapeLeft || orientation == .landscapeRight
        let width = sideways ? pointSize.height : pointSize.width
        return turned(CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// AXP hit testing accepts UIKit screen points, so invert the same
    /// rotation used for every element returned from that request.
    func unmap(_ point: CGPoint) -> CGPoint {
        if nativeRoot != nil { return point }
        switch orientation {
        case .portrait:
            return point
        case .portraitUpsideDown:
            return CGPoint(x: pointSize.width - point.x, y: pointSize.height - point.y)
        case .landscapeLeft:
            return CGPoint(x: pointSize.height - point.y, y: point.x)
        case .landscapeRight:
            return CGPoint(x: point.y, y: pointSize.width - point.x)
        }
    }
}
