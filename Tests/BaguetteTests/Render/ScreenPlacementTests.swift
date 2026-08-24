import Testing

@testable import BaguetteCore

@Suite("ScreenPlacement")
struct ScreenPlacementTests {
    @Test("stretch fills the screen surface without cropping or letterboxing")
    func stretchIsIdentity() {
        let placement = DeviceScreenFit.stretch.placement(
            source: RenderDimensions(width: 200, height: 100),
            target: RenderDimensions(width: 100, height: 100)
        )

        #expect(placement == ScreenPlacement(scaleX: 1, scaleY: 1, offsetX: 0, offsetY: 0))
    }

    @Test("cover crops the overflowing width of a wide frame on a square screen")
    func coverCropsWideSourceHorizontally() {
        let placement = DeviceScreenFit.cover.placement(
            source: RenderDimensions(width: 200, height: 100),
            target: RenderDimensions(width: 100, height: 100)
        )

        #expect(placement == ScreenPlacement(scaleX: 0.5, scaleY: 1, offsetX: 0.25, offsetY: 0))
    }

    @Test("cover crops the overflowing height of a tall frame on a square screen")
    func coverCropsTallSourceVertically() {
        let placement = DeviceScreenFit.cover.placement(
            source: RenderDimensions(width: 100, height: 200),
            target: RenderDimensions(width: 100, height: 100)
        )

        #expect(placement == ScreenPlacement(scaleX: 1, scaleY: 0.5, offsetX: 0, offsetY: 0.25))
    }

    @Test("contain letterboxes a wide frame vertically on a square screen")
    func containLetterboxesWideSourceVertically() {
        let placement = DeviceScreenFit.contain.placement(
            source: RenderDimensions(width: 200, height: 100),
            target: RenderDimensions(width: 100, height: 100)
        )

        #expect(placement == ScreenPlacement(scaleX: 1, scaleY: 2, offsetX: 0, offsetY: -0.5))
    }

    @Test("the feathered content region is the visible window inset by the border")
    func contentRegionInsetsVisibleWindow() {
        let identity = ScreenPlacement.identity.contentRegion(
            in: RenderDimensions(width: 100, height: 200),
            inset: 2
        )
        #expect(identity == ContentRegion(x: 2, y: 2, width: 96, height: 196))

        // cover crops a wide frame: only the central half of the width is
        // visible, so the border hugs that window instead of the texture.
        let cover = DeviceScreenFit.cover.placement(
            source: RenderDimensions(width: 200, height: 100),
            target: RenderDimensions(width: 100, height: 100)
        ).contentRegion(in: RenderDimensions(width: 200, height: 100), inset: 2)
        #expect(cover == ContentRegion(x: 52, y: 2, width: 96, height: 96))

        // contain letterboxes: the whole texture is visible.
        let contain = DeviceScreenFit.contain.placement(
            source: RenderDimensions(width: 200, height: 100),
            target: RenderDimensions(width: 100, height: 100)
        ).contentRegion(in: RenderDimensions(width: 200, height: 100), inset: 2)
        #expect(contain == ContentRegion(x: 2, y: 2, width: 196, height: 96))
    }

    @Test("matching aspect ratios need no adjustment for cover or contain")
    func matchingAspectIsIdentity() {
        for fit in [DeviceScreenFit.cover, .contain] {
            let placement = fit.placement(
                source: RenderDimensions(width: 660, height: 1434),
                target: RenderDimensions(width: 1320, height: 2868)
            )

            #expect(placement == ScreenPlacement(scaleX: 1, scaleY: 1, offsetX: 0, offsetY: 0))
        }
    }
}
