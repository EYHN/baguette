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
