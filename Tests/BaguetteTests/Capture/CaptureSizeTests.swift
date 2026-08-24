import Testing
@testable import BaguetteCore

@Suite("CaptureSize")
struct CaptureSizeTests {

    // ── the catalogue ────────────────────────────────────────

    @Test func `ships native first then the App Store sizes then the ratios`() {
        #expect(CaptureSize.presets.map(\.spec) == [
            "native",
            "appstore-6.9", "appstore-6.5", "appstore-ipad-13",
            "square", "16:9", "9:16", "4:3", "4:5",
        ])
    }

    @Test func `every preset carries a label for the picker and the help text`() {
        #expect(CaptureSize.presets.allSatisfy { !$0.label.isEmpty })
    }

    // ── parsing ──────────────────────────────────────────────

    @Test func `parses a preset name`() throws {
        #expect(try CaptureSize.parse("appstore-6.9").spec == "appstore-6.9")
    }

    @Test func `parses a preset name case-insensitively`() throws {
        #expect(try CaptureSize.parse("Appstore-6.9").spec == "appstore-6.9")
    }

    @Test func `parses a literal WxH`() throws {
        let size = try CaptureSize.parse("1920x1080")
        #expect(size.resolve(source: RenderDimensions(width: 400, height: 800))
            == RenderDimensions(width: 1920, height: 1080))
    }

    @Test func `parses an unlisted ratio`() throws {
        let size = try CaptureSize.parse("3:2")
        #expect(size.resolve(source: RenderDimensions(width: 600, height: 600))
            == RenderDimensions(width: 900, height: 600))
    }

    @Test func `rejects an unknown name rather than guessing`() {
        #expect(throws: CaptureSizeError.unknownSize("appstore")) {
            _ = try CaptureSize.parse("appstore")
        }
    }

    @Test func `rejects a zero dimension`() {
        #expect(throws: CaptureSizeError.unknownSize("0x100")) {
            _ = try CaptureSize.parse("0x100")
        }
    }

    // ── resolution ───────────────────────────────────────────

    @Test func `native resolves to the source untouched`() throws {
        let source = RenderDimensions(width: 1290, height: 2796)
        #expect(try CaptureSize.parse("native").resolve(source: source) == source)
    }

    @Test func `an App Store preset resolves to its fixed pixel size`() throws {
        #expect(try CaptureSize.parse("appstore-6.9")
            .resolve(source: RenderDimensions(width: 400, height: 800))
            == RenderDimensions(width: 1290, height: 2796))
    }

    // A ratio never downscales: it grows the binding axis so the source
    // still fits at 1:1. A portrait phone asked for `square` grows sideways.
    @Test func `square grows the narrow axis of a portrait source`() throws {
        #expect(try CaptureSize.parse("square")
            .resolve(source: RenderDimensions(width: 1290, height: 2796))
            == RenderDimensions(width: 2796, height: 2796))
    }

    @Test func `16 by 9 turns a portrait source into a landscape canvas`() throws {
        #expect(try CaptureSize.parse("16:9")
            .resolve(source: RenderDimensions(width: 1290, height: 2796))
            == RenderDimensions(width: 4971, height: 2796))
    }

    @Test func `a zero-sized source resolves to zero instead of dividing by zero`() throws {
        #expect(try CaptureSize.parse("square")
            .resolve(source: RenderDimensions(width: 0, height: 0))
            == RenderDimensions(width: 0, height: 0))
    }

    // ── placement ────────────────────────────────────────────

    @Test func `contain letterboxes the source and centres it`() throws {
        let plan = try CaptureSize.parse("square")
            .plan(source: RenderDimensions(width: 1000, height: 2000), fit: .contain)
        #expect(plan == CapturePlacement(
            width: 2000, height: 2000,
            drawX: 500, drawY: 0, drawWidth: 1000, drawHeight: 2000
        ))
    }

    @Test func `cover fills the canvas and lets the overflow crop`() throws {
        let plan = try CaptureSize.parse("square")
            .plan(source: RenderDimensions(width: 1000, height: 2000), fit: .cover)
        #expect(plan == CapturePlacement(
            width: 2000, height: 2000,
            drawX: 0, drawY: -1000, drawWidth: 2000, drawHeight: 4000
        ))
    }

    @Test func `stretch distorts the source to fill exactly`() throws {
        let plan = try CaptureSize.parse("1920x1080")
            .plan(source: RenderDimensions(width: 1000, height: 2000), fit: .stretch)
        #expect(plan == CapturePlacement(
            width: 1920, height: 1080,
            drawX: 0, drawY: 0, drawWidth: 1920, drawHeight: 1080
        ))
    }

    @Test func `native is a no-op placement whatever the fit`() throws {
        for fit in CaptureFit.allCases {
            #expect(try CaptureSize.parse("native")
                .plan(source: RenderDimensions(width: 1290, height: 2796), fit: fit)
                == CapturePlacement(
                    width: 1290, height: 2796,
                    drawX: 0, drawY: 0, drawWidth: 1290, drawHeight: 2796
                ), "fit: \(fit)")
        }
    }

    @Test func `native reports that it needs no resampling at all`() throws {
        let source = RenderDimensions(width: 1290, height: 2796)
        #expect(try CaptureSize.parse("native").plan(source: source, fit: .contain)
            .isIdentity(for: source))
        #expect(try !CaptureSize.parse("square").plan(source: source, fit: .contain)
            .isIdentity(for: source))
    }

    // Swift's `Double.rounded()` rounds half AWAY FROM ZERO; JavaScript's
    // `Math.round` rounds half UP. They agree on positive halves and
    // disagree on negative ones — which is exactly `cover`, the one case
    // where the draw origin goes negative. The two implementations of this
    // vocabulary have to place a frame on the same pixel, so the Swift side
    // rounds half up too. `Tests/Web/capture-size.test.js` asserts the
    // identical numbers.
    @Test func `a cover overflow rounds the same way JavaScript does`() throws {
        let plan = try CaptureSize.parse("square")
            .plan(source: RenderDimensions(width: 1000, height: 2001), fit: .cover)
        #expect(plan.drawY == -1001)   // not -1002
        #expect(plan.width == 2001)
        #expect(plan.drawHeight == 4004)
    }

    // ── fit parsing ──────────────────────────────────────────

    @Test func `fit parses from its wire spelling`() {
        #expect(CaptureFit(rawValue: "contain") == .contain)
        #expect(CaptureFit(rawValue: "cover") == .cover)
        #expect(CaptureFit(rawValue: "stretch") == .stretch)
        #expect(CaptureFit(rawValue: "wat") == nil)
    }
}
