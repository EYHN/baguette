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
        given(hinge).angle().willReturn(HingeAngle(degrees: 130))
        given(hinge).watch(onAngle: .any).willReturn(watch)
        given(watch).cancel().willReturn()
        given(scene).update(hingeDegrees: .any).willReturn()
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
        given(hinge).angle().willReturn(HingeAngle(degrees: 130))
        given(hinge).watch(onAngle: .any).willProduce { onAngle = $0; return watch }
        given(scene).update(hingeDegrees: .any).willReturn()
        let renders = LockedCount()
        given(scene).render(screens: .any).willProduce { _ in renders.increment(); return rendered }
        let screen = RenderedFoldable(unfolded: unfolded, cover: cover, hinge: hinge, scene: scene)
        try screen.start { _ in }
        innerDelivery?(inner)
        #expect(RenderedScreenTests.waitUntil { renders.value == 1 })

        onAngle?(HingeAngle(degrees: 120))

        #expect(RenderedScreenTests.waitUntil { renders.value == 2 })
        verify(scene).update(hingeDegrees: .value(120)).called(1)
    }

    @Test func `the pose shown is the hinge's own angle`() throws {
        let unfolded = MockScreen(), cover = MockScreen()
        let hinge = MockHinge(), watch = MockHingeWatch()
        let scene = MockDeviceScene()
        var onAngle: ((HingeAngle) -> Void)?
        given(unfolded).start(onFrame: .any).willReturn()
        given(cover).start(onFrame: .any).willReturn()
        given(hinge).angle().willReturn(HingeAngle(degrees: 130))
        given(hinge).watch(onAngle: .any).willProduce { onAngle = $0; return watch }
        given(scene).update(hingeDegrees: .any).willReturn()
        let screen = RenderedFoldable(unfolded: unfolded, cover: cover, hinge: hinge, scene: scene)
        try screen.start { _ in }
        #expect(screen.pose == FoldablePose(hingeDegrees: 130))
        onAngle?(HingeAngle(degrees: 42))
        #expect(screen.pose == FoldablePose(hingeDegrees: 42))
    }

    @Test func `the book is posed at the standing angle before any frame is composed`() throws {
        // A scene starts flat; a frame composed before the hinge has
        // spoken would show the book open when it is shut.
        let unfolded = MockScreen(), cover = MockScreen()
        let hinge = MockHinge(), watch = MockHingeWatch()
        let scene = MockDeviceScene()
        let inner = try #require(RenderedScreenTests.surface(width: 2, height: 2))
        let rendered = try #require(RenderedScreenTests.surface(width: 4, height: 3))
        var innerDelivery: (@Sendable (IOSurface) -> Void)?
        var onAngle: ((HingeAngle) -> Void)?
        given(unfolded).start(onFrame: .any).willProduce { innerDelivery = $0 }
        given(cover).start(onFrame: .any).willReturn()
        given(hinge).angle().willReturn(HingeAngle(degrees: 0))
        given(hinge).watch(onAngle: .any).willProduce { onAngle = $0; return watch }
        let order = LockedLog()
        given(scene).update(hingeDegrees: .any).willProduce { order.append("pose \($0)") }
        given(scene).render(screens: .any).willProduce { _ in order.append("render"); return rendered }
        let screen = RenderedFoldable(unfolded: unfolded, cover: cover, hinge: hinge, scene: scene)

        try screen.start { _ in }
        innerDelivery?(inner)
        #expect(RenderedScreenTests.waitUntil { order.value.contains("render") })
        #expect(order.value.first == "pose 0.0")

        // With no standing angle — the guest's motion stream can be
        // silent — the book is shown shut, as it boots, until the hinge
        // speaks: a blank stage helps nobody.
        let mute = MockHinge()
        given(mute).angle().willReturn(nil)
        given(mute).watch(onAngle: .any).willProduce { onAngle = $0; return watch }
        let late = LockedLog()
        let scene2 = MockDeviceScene()
        given(scene2).update(hingeDegrees: .any).willProduce { late.append("pose \($0)") }
        given(scene2).render(screens: .any).willProduce { _ in late.append("render"); return rendered }
        let unfolded2 = MockScreen(), cover2 = MockScreen()
        var delivery2: (@Sendable (IOSurface) -> Void)?
        given(unfolded2).start(onFrame: .any).willProduce { delivery2 = $0 }
        given(cover2).start(onFrame: .any).willReturn()
        let waiting = RenderedFoldable(unfolded: unfolded2, cover: cover2, hinge: mute, scene: scene2)
        try waiting.start { _ in }
        delivery2?(inner)
        #expect(RenderedScreenTests.waitUntil { late.value == ["pose 0.0", "render"] })
        onAngle?(HingeAngle(degrees: 3.8))
        #expect(RenderedScreenTests.waitUntil { late.value == ["pose 0.0", "render", "pose 3.8", "render"] })
    }
}

private final class LockedScreens: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [FoldableScreens] = []
    var value: [FoldableScreens] { lock.withLock { storage } }
    func append(_ screens: FoldableScreens) { lock.withLock { storage.append(screens) } }
}

private final class LockedLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var value: [String] { lock.withLock { storage } }
    func append(_ entry: String) { lock.withLock { storage.append(entry) } }
}

private final class LockedCount: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    var value: Int { lock.withLock { storage } }
    func increment() { lock.withLock { storage += 1 } }
}
