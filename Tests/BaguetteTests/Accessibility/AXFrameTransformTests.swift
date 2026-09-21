import Testing
import CoreGraphics
@testable import Baguette

/// `AXFrameTransform` projects mac-window-coordinate CGRects from
/// AXPTranslator into device-point CGRects (the same units the
/// gesture wire uses). Width-uniform scale + vertical centering
/// offset matches Simulator.app's letterbox layout for tall
/// devices in a short window.
@Suite("AXFrameTransform")
struct AXFrameTransformTests {

    // MARK: - happy path: square mapping (rootFrame matches device aspect)

    @Test func `1:1 root → identity scale, no y-offset`() {
        let t = AXFrameTransform(
            rootFrame: CGRect(x: 0, y: 0, width: 393, height: 852),
            pointSize: CGSize(width: 393, height: 852)
        )
        let mapped = t.map(CGRect(x: 100, y: 200, width: 50, height: 60))
        #expect(mapped == CGRect(x: 100, y: 200, width: 50, height: 60))
    }

    @Test func `2:1 root → halves coordinates uniformly`() {
        let t = AXFrameTransform(
            rootFrame: CGRect(x: 0, y: 0, width: 786, height: 1704),
            pointSize: CGSize(width: 393, height: 852)
        )
        let mapped = t.map(CGRect(x: 200, y: 400, width: 100, height: 80))
        #expect(mapped == CGRect(x: 100, y: 200, width: 50, height: 40))
    }

    // MARK: - origin offset: rootFrame moved away from (0,0)

    @Test func `non-zero root origin shifts the mapped origin back to device-space`() {
        let t = AXFrameTransform(
            rootFrame: CGRect(x: 50, y: 80, width: 393, height: 852),
            pointSize: CGSize(width: 393, height: 852)
        )
        let mapped = t.map(CGRect(x: 60, y: 90, width: 30, height: 30))
        #expect(mapped == CGRect(x: 10, y: 10, width: 30, height: 30))
    }

    // MARK: - letterbox: rootFrame is wider than device, leaves vertical slack

    @Test func `wider-than-tall root injects a positive y centering offset`() {
        // pointSize is 100x200 (1:2 portrait); rootFrame is 100 wide
        // and 100 tall. Width-scale = 1; the device's logical 200 height
        // exceeds rootFrame.height * scale (100), leaving 100pt of
        // slack split evenly above + below → +50 on every y.
        let t = AXFrameTransform(
            rootFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            pointSize: CGSize(width: 100, height: 200)
        )
        let mapped = t.map(CGRect(x: 10, y: 20, width: 30, height: 40))
        #expect(mapped == CGRect(x: 10, y: 70, width: 30, height: 40))
    }

    // MARK: - degenerate inputs → identity (don't divide by zero)

    @Test func `zero-width root falls back to identity`() {
        let t = AXFrameTransform(
            rootFrame: CGRect(x: 0, y: 0, width: 0, height: 100),
            pointSize: CGSize(width: 100, height: 100)
        )
        let input = CGRect(x: 5, y: 6, width: 7, height: 8)
        #expect(t.map(input) == input)
    }

    @Test func `zero-height root falls back to identity`() {
        let t = AXFrameTransform(
            rootFrame: CGRect(x: 0, y: 0, width: 100, height: 0),
            pointSize: CGSize(width: 100, height: 100)
        )
        let input = CGRect(x: 5, y: 6, width: 7, height: 8)
        #expect(t.map(input) == input)
    }

    @Test func `zero-width pointSize falls back to identity`() {
        let t = AXFrameTransform(
            rootFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            pointSize: CGSize(width: 0, height: 100)
        )
        let input = CGRect(x: 5, y: 6, width: 7, height: 8)
        #expect(t.map(input) == input)
    }

    @Test func `zero-height pointSize falls back to identity`() {
        let t = AXFrameTransform(
            rootFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            pointSize: CGSize(width: 100, height: 0)
        )
        let input = CGRect(x: 5, y: 6, width: 7, height: 8)
        #expect(t.map(input) == input)
    }

    // MARK: - unmap: device-point → mac-host coordinate, the inverse
    // path used by the AXP server-side hit-test.

    @Test func `unmap is the inverse of map for the identity transform`() {
        let t = AXFrameTransform(
            rootFrame: CGRect(x: 0, y: 0, width: 393, height: 852),
            pointSize: CGSize(width: 393, height: 852)
        )
        #expect(t.unmap(CGPoint(x: 100, y: 200)) == CGPoint(x: 100, y: 200))
    }

    @Test func `unmap reverses a 2:1 down-scale into an up-scale`() {
        let t = AXFrameTransform(
            rootFrame: CGRect(x: 0, y: 0, width: 786, height: 1704),
            pointSize: CGSize(width: 393, height: 852)
        )
        // device (100, 200) corresponds to host (200, 400) — exactly
        // reversing the `2:1 root → halves coordinates uniformly` map.
        #expect(t.unmap(CGPoint(x: 100, y: 200)) == CGPoint(x: 200, y: 400))
    }

    @Test func `unmap reverses a non-zero root origin shift`() {
        let t = AXFrameTransform(
            rootFrame: CGRect(x: 50, y: 80, width: 393, height: 852),
            pointSize: CGSize(width: 393, height: 852)
        )
        // device (10, 10) → host (60, 90), inverse of the existing
        // map-side origin-shift test.
        #expect(t.unmap(CGPoint(x: 10, y: 10)) == CGPoint(x: 60, y: 90))
    }

    @Test func `unmap reverses the letterbox y-offset`() {
        // Same letterbox setup as the map test: pointSize 100x200,
        // rootFrame 100x100 → +50 y centering offset.
        let t = AXFrameTransform(
            rootFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            pointSize: CGSize(width: 100, height: 200)
        )
        // device (10, 70) → host (10, 20), inverse of the map test
        // mapping (10, 20) → (10, 70).
        #expect(t.unmap(CGPoint(x: 10, y: 70)) == CGPoint(x: 10, y: 20))
    }

    @Test func `unmap falls back to identity on degenerate inputs`() {
        let zeroRoot = AXFrameTransform(
            rootFrame: CGRect(x: 0, y: 0, width: 0, height: 100),
            pointSize: CGSize(width: 100, height: 100)
        )
        #expect(zeroRoot.unmap(CGPoint(x: 5, y: 6)) == CGPoint(x: 5, y: 6))

        let zeroPoint = AXFrameTransform(
            rootFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            pointSize: CGSize(width: 100, height: 0)
        )
        #expect(zeroPoint.unmap(CGPoint(x: 5, y: 6)) == CGPoint(x: 5, y: 6))
    }

    // MARK: - landscape: the UI reports its root sideways to the panel

    /// Measured on iPhone 17 (402×874 pt) running Safari landscape: AXP
    /// reports the root as (0, 0, 874, 402) and SimulatorKit's
    /// `uiOrientation` as 3. The portrait-only transform scaled by
    /// 402/874 and centred vertically, describing the whole UI as a
    /// 402×185 band at y≈344; every element frame was off and taps
    /// through `unmap` landed on nothing.
    @Test func `landscape root fills the portrait panel instead of a letterboxed band`() {
        let t = AXFrameTransform.presenting(
            rootFrame: CGRect(x: 0, y: 0, width: 874, height: 402),
            pointSize: CGSize(width: 402, height: 874),
            orientation: .landscapeRight
        )
        let root = t.map(CGRect(x: 0, y: 0, width: 874, height: 402))
        #expect(root == CGRect(x: 0, y: 0, width: 402, height: 874))
    }

    /// The "Customize Start Page" button: AXP frame centred at
    /// (524, 242) in the upright 874×402 UI; on screen its centre is at
    /// (242, 350) of the portrait framebuffer (the UI's top edge runs
    /// along the panel's left edge).
    @Test func `landscape-right turns the upright UI onto the panel with its top on the left`() {
        let t = AXFrameTransform.presenting(
            rootFrame: CGRect(x: 0, y: 0, width: 874, height: 402),
            pointSize: CGSize(width: 402, height: 874),
            orientation: .landscapeRight
        )
        let mapped = t.map(CGRect(x: 504, y: 222, width: 40, height: 40))
        #expect(abs(mapped.midX - 242) < 0.001)
        #expect(abs(mapped.midY - 350) < 0.001)
        #expect(mapped.size == CGSize(width: 40, height: 40))
        // And back: the point a tap lands on resolves to the same element.
        let back = t.unmap(CGPoint(x: 242, y: 350))
        #expect(abs(back.x - 524) < 0.001)
        #expect(abs(back.y - 242) < 0.001)
    }

    @Test func `landscape-left is the mirror turn`() {
        let t = AXFrameTransform.presenting(
            rootFrame: CGRect(x: 0, y: 0, width: 874, height: 402),
            pointSize: CGSize(width: 402, height: 874),
            orientation: .landscapeLeft
        )
        // Upright top-left corner lands at the panel's top-right.
        let corner = t.map(CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(abs(corner.maxX - 402) < 0.001)
        #expect(abs(corner.minY - 0) < 0.001)
        let back = t.unmap(CGPoint(x: 397, y: 5))
        #expect(abs(back.x - 5) < 0.001)
        #expect(abs(back.y - 5) < 0.001)
    }

    /// A panel mounted sideways (iPhone Duo's inner display) reports
    /// the elements upright but the root as the panel's own portrait
    /// rectangle; that root is restated so the elements scale on the
    /// right axis, and the root itself maps to the whole panel.
    @Test func `a portrait-shaped root under a landscape UI is restated as the upright frame`() {
        let t = AXFrameTransform.presenting(
            rootFrame: CGRect(x: 0, y: 0, width: 402, height: 874),
            pointSize: CGSize(width: 402, height: 874),
            orientation: .landscapeRight
        )
        #expect(t.rootFrame == CGRect(x: 0, y: 0, width: 874, height: 402))
        #expect(t.map(CGRect(x: 0, y: 0, width: 402, height: 874)) == CGRect(x: 0, y: 0, width: 402, height: 874))
    }

    @Test func `portrait keeps the letterbox mapping unchanged`() {
        let t = AXFrameTransform.presenting(
            rootFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            pointSize: CGSize(width: 100, height: 200),
            orientation: .portrait
        )
        #expect(t == AXFrameTransform(rootFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                      pointSize: CGSize(width: 100, height: 200)))
        #expect(t.map(CGRect(x: 10, y: 20, width: 30, height: 40)) == CGRect(x: 10, y: 70, width: 30, height: 40))
    }
}
