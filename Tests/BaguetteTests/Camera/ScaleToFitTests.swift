import Testing
@testable import BaguetteCore

@Suite("ScaleToFit")
struct ScaleToFitTests {

    @Test func `dimensions already within the cap pass through untouched`() {
        let fitted = ScaleToFit.fit(width: 800, height: 600, max: 1280)
        #expect(fitted.width == 800)
        #expect(fitted.height == 600)
    }

    @Test func `an oversized landscape frame clamps its long edge to the cap`() {
        let fitted = ScaleToFit.fit(width: 1920, height: 1080, max: 1280)
        #expect(fitted.width == 1280)
        #expect(fitted.height == 720)
    }

    @Test func `an oversized portrait frame clamps its long edge to the cap`() {
        let fitted = ScaleToFit.fit(width: 1080, height: 1920, max: 1280)
        #expect(fitted.width == 720)
        #expect(fitted.height == 1280)
    }

    @Test func `an oversized square frame fills the cap exactly`() {
        let fitted = ScaleToFit.fit(width: 2560, height: 2560, max: 1280)
        #expect(fitted.width == 1280)
        #expect(fitted.height == 1280)
    }

    @Test func `the shorter edge is rounded, never zero`() {
        let fitted = ScaleToFit.fit(width: 1000, height: 3000, max: 1280)
        #expect(fitted.height == 1280)
        #expect(fitted.width == 427)  // round(1000 * 1280/3000)
    }
}
