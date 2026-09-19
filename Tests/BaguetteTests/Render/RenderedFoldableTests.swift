import Foundation
import IOSurface
import Mockable
import Testing
@testable import Baguette

// A foldable has two screens and a hinge. Frames from either panel
// compose through one scene, posed at the hinge's latest angle, with the
// latest frame of each panel on its screen.
@Suite("RenderedFoldable")
struct RenderedFoldableTests {
    @Test func `a frame from either panel renders with the latest frame of both`() throws {
        let unfolded = MockScreen(), cover = MockScreen()
        let hinge = MockHinge(), watch = MockHingeWatch()
        let scene = MockDeviceScene()
        let inner = try #require(RenderedScreenTests.surface(width: 2, height: 2))
        let outer = try #require(RenderedScreenTests.surface(width: 3, height: 3))
        let rendered = try #require(RenderedScreenTests.surface(width: 4, height: 3))
        var innerDelivery: (@Sendable (IOSurface) -> Void)?
        var coverDelivery: (@Sendable (IOSurface) -> Void)?
        given(unfolded).start(onFrame: .any).willProduce { innerDelivery = $0 }
        given(cover).start(onFrame: .any).willProduce { coverDelivery = $0 }
        given(unfolded).stop().willReturn()
        given(cover).stop().willReturn()
        given(hinge).watch(onAngle: .any).willReturn(watch)
        given(watch).cancel().willReturn()
        let seen = LockedScreens()
        given(scene).render(screens: .any).willProduce { screens in
            seen.append(screens); return rendered
        }
        let screen = RenderedFoldable(unfolded: unfolded, cover: cover, hinge: hinge, scene: scene)
        let delivered = LockedCount()

        try screen.start { _ in delivered.increment() }
        innerDelivery?(inner)
        #expect(RenderedScreenTests.waitUntil { delivered.value == 1 })
        coverDelivery?(outer)
        #expect(RenderedScreenTests.waitUntil { delivered.value == 2 })
        screen.stop()

        #expect(seen.value == [
            FoldableScreens(unfolded: inner, cover: nil),
            FoldableScreens(unfolded: inner, cover: outer),
        ])
        verify(unfolded).stop().called(1)
        verify(cover).stop().called(1)
        verify(watch).cancel().called(1)
    }

    @Test func `a hinge sample poses the scene and recomposes the latest frames`() throws {
        let unfolded = MockScreen(), cover = MockScreen()
        let hinge = MockHinge(), watch = MockHingeWatch()
        let scene = MockDeviceScene()
        let inner = try #require(RenderedScreenTests.surface(width: 2, height: 2))
        let rendered = try #require(RenderedScreenTests.surface(width: 4, height: 3))
        var innerDelivery: (@Sendable (IOSurface) -> Void)?
        var onAngle: ((HingeAngle) -> Void)?
        given(unfolded).start(onFrame: .any).willProduce { innerDelivery = $0 }
        given(cover).start(onFrame: .any).willReturn()
        given(hinge).watch(onAngle: .any).willProduce { onAngle = $0; return watch }
        given(scene).update(hingeDegrees: .any).willReturn()
        let renders = LockedCount()
        given(scene).render(screens: .any).willProduce { _ in renders.increment(); return rendered }
        let screen = RenderedFoldable(unfolded: unfolded, cover: cover, hinge: hinge, scene: scene)
        try screen.start { _ in }
        innerDelivery?(inner)
        #expect(RenderedScreenTests.waitUntil { renders.value == 1 })

        onAngle?(HingeAngle(degrees: 130))

        #expect(RenderedScreenTests.waitUntil { renders.value == 2 })
        verify(scene).update(hingeDegrees: .value(130)).called(1)
    }
}

private final class LockedScreens: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [FoldableScreens] = []
    var value: [FoldableScreens] { lock.withLock { storage } }
    func append(_ screens: FoldableScreens) { lock.withLock { storage.append(screens) } }
}

private final class LockedCount: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    var value: Int { lock.withLock { storage } }
    func increment() { lock.withLock { storage += 1 } }
}
