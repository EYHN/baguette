import Testing
@testable import BaguetteCore

/// Given a display binding and live surface sizes, pick which plane to
/// emit. CarPlay must never fall back to the phone framebuffer.
@Suite("FramebufferSurfacePick")
struct FramebufferSurfacePickTests {
    private let phoneBinding = DisplayBinding(
        kind: .phone,
        connectedScreenId: 1,
        portName: "com.apple.framebuffer.display",
        size: Size(width: 1206, height: 2622)
    )
    private let carPlayBinding = DisplayBinding(
        kind: .carPlay,
        connectedScreenId: 2,
        portName: "com.apple.framebuffer.display",
        size: Size(width: 800, height: 480)
    )

    @Test func phonePicksClosestToBindingSize() {
        let index = FramebufferSurfacePick.index(
            binding: phoneBinding,
            candidates: [
                Size(width: 100, height: 100),
                Size(width: 1206, height: 2622),
                Size(width: 800, height: 480),
            ]
        )
        #expect(index == 1)
    }

    @Test func carPlayPicksLandscapeNearBindingAndSkipsPhone() {
        let index = FramebufferSurfacePick.index(
            binding: carPlayBinding,
            candidates: [
                Size(width: 1206, height: 2622),
                Size(width: 800, height: 480),
                Size(width: 100, height: 100),
            ]
        )
        #expect(index == 1)
    }

    @Test func carPlayReturnsNilWhenOnlyPhoneSurfacesArePresent() {
        let index = FramebufferSurfacePick.index(
            binding: carPlayBinding,
            candidates: [
                Size(width: 1206, height: 2622),
                Size(width: 1179, height: 2556),
            ]
        )
        #expect(index == nil)
    }

    /// The external plane used to refuse anything above 800×480×4 —
    /// a leftover from when this pane was only ever CarPlay, whose
    /// screen is 720×480. The I/O → External Displays menu offers
    /// ordinary resolutions too, and a 1080p one is a perfectly good
    /// display to stream; rejecting it just reported "nothing attached"
    /// at a screen the user was looking at.
    @Test func `a full-HD external is a candidate`() {
        #expect(FramebufferSurfacePick.acceptsExternal(Size(width: 1920, height: 1080)))
        #expect(FramebufferSurfacePick.acceptsExternal(Size(width: 3840, height: 2160)))
    }

    /// Landscape is the check that still earns its keep: it is what
    /// keeps a portrait phone plane out of the external pane when the
    /// largest-area heuristic has already spent itself on some other
    /// port. Mirroring SpringBoard into the external pane is worse than
    /// showing nothing, because it looks like it worked.
    @Test func `a portrait plane is never an external candidate`() {
        #expect(!FramebufferSurfacePick.acceptsExternal(Size(width: 1206, height: 2622)))
        #expect(!FramebufferSurfacePick.acceptsExternal(Size(width: 1179, height: 2556)))
    }

    /// Landscape means *wider than tall*. A square is neither the
    /// device's shape nor a display's, and admitting it means any square
    /// scratch buffer big enough to clear the area floor can bind as the
    /// external plane.
    @Test func `a square surface is not landscape`() {
        #expect(!FramebufferSurfacePick.acceptsExternal(Size(width: 512, height: 512)))
        #expect(!FramebufferSurfacePick.acceptsExternal(Size(width: 1080, height: 1080)))
    }

    @Test func `a degenerate sliver is not a display`() {
        #expect(!FramebufferSurfacePick.acceptsExternal(Size(width: 100, height: 100)))
        #expect(!FramebufferSurfacePick.acceptsExternal(Size(width: 0, height: 0)))
    }

    @Test func `a large landscape surface is picked for a large binding`() {
        let binding = DisplayBinding(
            kind: .carPlay,
            connectedScreenId: 2,
            portName: "com.apple.framebuffer.display",
            size: Size(width: 1920, height: 1080)
        )
        let index = FramebufferSurfacePick.index(
            binding: binding,
            candidates: [
                Size(width: 1206, height: 2622),
                Size(width: 1920, height: 1080),
            ]
        )
        #expect(index == 1)
    }

    @Test func unboundScreenFallsBackToLargestArea() {
        let index = FramebufferSurfacePick.index(
            binding: nil,
            candidates: [
                Size(width: 800, height: 480),
                Size(width: 1206, height: 2622),
            ]
        )
        #expect(index == 1)
    }
}
