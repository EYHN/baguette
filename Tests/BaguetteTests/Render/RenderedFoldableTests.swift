import Foundation
import IOSurface
import Mockable
import Testing
@testable import BaguetteCore

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
        given(unfolded).start(onFrame: .any, onMetadata: .any).willProduce { onFrame, _ in innerDelivery = onFrame }
        given(cover).start(onFrame: .any, onMetadata: .any).willProduce { onFrame, _ in coverDelivery = onFrame }
        given(unfolded).stop().willReturn()
        given(cover).stop().willReturn()
        given(hinge).angle().willReturn(HingeAngle(degrees: 130))
        given(hinge).watch(onAngle: .any, onEnd: .any).willReturn(watch)
        given(watch).cancel().willReturn()
        given(scene).update(hingeDegrees: .any, litPanel: .any).willReturn()
        let seen = LockedScreens()
        given(scene).render(screens: .any).willProduce { screens in
            seen.append(screens); return rendered
        }
        let screen = RenderedFoldable(unfolded: unfolded, cover: cover, hinge: hinge, litPanel: { .secondary }, scene: scene)
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
        given(unfolded).start(onFrame: .any, onMetadata: .any).willProduce { onFrame, _ in innerDelivery = onFrame }
        given(cover).start(onFrame: .any, onMetadata: .any).willReturn()
        given(hinge).angle().willReturn(HingeAngle(degrees: 130))
        given(hinge).watch(onAngle: .any, onEnd: .any).willProduce { cb, _ in onAngle = cb; return watch }
        given(scene).update(hingeDegrees: .any, litPanel: .any).willReturn()
        let renders = LockedCount()
        given(scene).render(screens: .any).willProduce { _ in renders.increment(); return rendered }
        let screen = RenderedFoldable(unfolded: unfolded, cover: cover, hinge: hinge, litPanel: { .secondary }, scene: scene)
        try screen.start { _ in }
        innerDelivery?(inner)
        #expect(RenderedScreenTests.waitUntil { renders.value == 1 })

        onAngle?(HingeAngle(degrees: 120))

        #expect(RenderedScreenTests.waitUntil { renders.value == 2 })
        verify(scene).update(hingeDegrees: .value(120), litPanel: .value(.secondary)).called(1)
    }

    @Test func `the pose shown is the hinge's own angle`() throws {
        let unfolded = MockScreen(), cover = MockScreen()
        let hinge = MockHinge(), watch = MockHingeWatch()
        let scene = MockDeviceScene()
        var onAngle: ((HingeAngle) -> Void)?
        given(unfolded).start(onFrame: .any, onMetadata: .any).willReturn()
        given(cover).start(onFrame: .any, onMetadata: .any).willReturn()
        given(hinge).angle().willReturn(HingeAngle(degrees: 130))
        given(hinge).watch(onAngle: .any, onEnd: .any).willProduce { cb, _ in onAngle = cb; return watch }
        given(scene).update(hingeDegrees: .any, litPanel: .any).willReturn()
        let screen = RenderedFoldable(unfolded: unfolded, cover: cover, hinge: hinge, litPanel: { .secondary }, scene: scene)
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
        given(unfolded).start(onFrame: .any, onMetadata: .any).willProduce { onFrame, _ in innerDelivery = onFrame }
        given(cover).start(onFrame: .any, onMetadata: .any).willReturn()
        given(hinge).angle().willReturn(HingeAngle(degrees: 0))
        given(hinge).watch(onAngle: .any, onEnd: .any).willProduce { cb, _ in onAngle = cb; return watch }
        let order = LockedLog()
        given(scene).update(hingeDegrees: .any, litPanel: .any).willProduce { degrees, _ in order.append("pose \(degrees)") }
        given(scene).render(screens: .any).willProduce { _ in order.append("render"); return rendered }
        let screen = RenderedFoldable(unfolded: unfolded, cover: cover, hinge: hinge, litPanel: { .secondary }, scene: scene)

        try screen.start { _ in }
        innerDelivery?(inner)
        #expect(RenderedScreenTests.waitUntil { order.value.contains("render") })
        #expect(order.value.first == "pose 0.0")

        // With no standing angle — the guest's motion stream can be
        // silent — the book is shown shut, as it boots, until the hinge
        // speaks: a blank stage helps nobody.
        let mute = MockHinge()
        given(mute).angle().willReturn(nil)
        given(mute).watch(onAngle: .any, onEnd: .any).willProduce { cb, _ in onAngle = cb; return watch }
        let late = LockedLog()
        let scene2 = MockDeviceScene()
        given(scene2).update(hingeDegrees: .any, litPanel: .any).willProduce { degrees, _ in late.append("pose \(degrees)") }
        given(scene2).render(screens: .any).willProduce { _ in late.append("render"); return rendered }
        let unfolded2 = MockScreen(), cover2 = MockScreen()
        var delivery2: (@Sendable (IOSurface) -> Void)?
        given(unfolded2).start(onFrame: .any, onMetadata: .any).willProduce { onFrame, _ in delivery2 = onFrame }
        given(cover2).start(onFrame: .any, onMetadata: .any).willReturn()
        let waiting = RenderedFoldable(unfolded: unfolded2, cover: cover2, hinge: mute, litPanel: { .primary }, scene: scene2)
        try waiting.start { _ in }
        delivery2?(inner)
        #expect(RenderedScreenTests.waitUntil { late.value == ["pose 0.0", "render"] })
        onAngle?(HingeAngle(degrees: 3.8))
        #expect(RenderedScreenTests.waitUntil { late.value == ["pose 0.0", "render", "pose 3.8", "render"] })
    }

    /// The lit panel is Core Device's word, handed to the scene with the
    /// angle — never derived from it. When it changes without the hinge
    /// moving (the pose provider settling late, an app claiming the
    /// cover), the book is re-posed before the next frame is composed.
    @Test func `the lit panel is what the source says, and a change re-poses before the next frame`() throws {
        let unfolded = MockScreen(), cover = MockScreen()
        let hinge = MockHinge(), watch = MockHingeWatch()
        let scene = MockDeviceScene()
        let inner = try #require(RenderedScreenTests.surface(width: 2, height: 2))
        let rendered = try #require(RenderedScreenTests.surface(width: 4, height: 3))
        var innerDelivery: (@Sendable (IOSurface) -> Void)?
        given(unfolded).start(onFrame: .any, onMetadata: .any).willProduce { onFrame, _ in innerDelivery = onFrame }
        given(cover).start(onFrame: .any, onMetadata: .any).willReturn()
        // 30° on the way shut: the unfolded panel is still lit.
        given(hinge).angle().willReturn(HingeAngle(degrees: 30))
        given(hinge).watch(onAngle: .any, onEnd: .any).willReturn(watch)
        let lit = LockedPanel(.secondary)
        let order = LockedLog()
        given(scene).update(hingeDegrees: .any, litPanel: .any).willProduce { degrees, panel in
            order.append("pose \(degrees) \(panel)")
        }
        given(scene).render(screens: .any).willProduce { _ in order.append("render"); return rendered }
        let poses = LockedCount()
        let screen = RenderedFoldable(
            unfolded: unfolded, cover: cover, hinge: hinge, litPanel: { lit.value }, scene: scene,
            onPose: { poses.increment() }
        )
        try screen.start { _ in }
        innerDelivery?(inner)
        #expect(RenderedScreenTests.waitUntil { order.value == ["pose 30.0 secondary", "render"] })

        // SpringBoard hands over to the cover a moment later, hinge still.
        lit.value = .primary
        innerDelivery?(inner)
        #expect(RenderedScreenTests.waitUntil { order.value.count == 4 })
        #expect(order.value == ["pose 30.0 secondary", "render", "pose 30.0 primary", "render"])
        #expect(poses.value == 1)
    }
}

private final class LockedPanel: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: IntegratedPanel
    init(_ panel: IntegratedPanel) { storage = panel }
    var value: IntegratedPanel {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
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
