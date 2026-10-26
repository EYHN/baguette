import CoreGraphics
import Testing

@testable import Baguette

@Suite("AXFrameTransform")
struct AXFrameTransformTests {
    @Test(arguments: [
        (DeviceOrientation.portrait, CGRect(x: 50, y: 80, width: 84, height: 48)),
        (.portraitUpsideDown, CGRect(x: 268, y: 746, width: 84, height: 48)),
        (.landscapeLeft, CGRect(x: 80, y: 740, width: 48, height: 84)),
        (.landscapeRight, CGRect(x: 274, y: 50, width: 48, height: 84)),
    ])
    func `noncentral UIKit rectangles and hit tests use native panel coordinates`(
        orientation: DeviceOrientation, expected: CGRect
    ) {
        let transform = AXFrameTransform(
            pointSize: CGSize(width: 402, height: 874), orientation: orientation
        )
        let raw = CGRect(x: 50, y: 80, width: 84, height: 48)
        let mapped = transform.map(raw)
        #expect(mapped == expected)
        #expect(transform.unmap(CGPoint(x: mapped.midX, y: mapped.midY)) == CGPoint(x: raw.midX, y: raw.midY))
    }
}

@Suite("AXFrameTransform.presenting")
struct AXFrameTransformPresentingTests {
    /// Measured on an unfolded iPhone Duo (inner panel 669 × 951 pt): AXP
    /// reports a landscape UI's elements in the upright 951 × 669 frame
    /// but the application root as the panel's portrait 669 × 951.
    @Test func `a portrait-shaped root under a landscape UI is the whole panel`() {
        let panel = CGSize(width: 669, height: 951)
        let root = CGRect(x: 0, y: 0, width: 669, height: 951)
        let transform = AXFrameTransform.presenting(rootFrame: root, pointSize: panel, orientation: .landscapeLeft)
        #expect(transform.map(root) == CGRect(origin: .zero, size: panel))
        // Every other frame still turns with the UI.
        let plain = AXFrameTransform(pointSize: panel, orientation: .landscapeLeft)
        let element = CGRect(x: 84, y: 304, width: 527, height: 52)
        #expect(transform.map(element) == plain.map(element))
    }

    @Test func `a root that already matches its UI is rotated like any frame`() {
        let panel = CGSize(width: 402, height: 874)
        let landscape = CGRect(x: 0, y: 0, width: 874, height: 402)
        let transform = AXFrameTransform.presenting(rootFrame: landscape, pointSize: panel, orientation: .landscapeRight)
        #expect(transform.panelShapedRoot == nil)
        #expect(transform.map(landscape) == CGRect(origin: .zero, size: panel))
        let portrait = CGRect(origin: .zero, size: panel)
        #expect(AXFrameTransform.presenting(rootFrame: portrait, pointSize: panel, orientation: .portrait).panelShapedRoot == nil)
    }
}
