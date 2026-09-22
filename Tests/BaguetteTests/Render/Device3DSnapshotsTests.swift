import Foundation
import IOSurface
import Mockable
import Testing
@testable import BaguetteCore

/// A still of the device on its 3D model for an agent to look at. The
/// scene stays warm per device; each shot paints the panels' frames,
/// poses the book at the hinge's angle with Core Device's lit panel,
/// and renders.
@Suite("Device3DSnapshots")
struct Device3DSnapshotsTests {

    static func duo() throws -> InstalledDeviceModel {
        InstalledDeviceModel(
            definition: try DeviceModelDefinition.parsing(json: Data(FoldableModelDefinitionTests.duoJSON.utf8)),
            directoryURL: URL(fileURLWithPath: "/tmp/duo")
        )
    }

    static func phone() throws -> InstalledDeviceModel {
        let json = #"""
        {
          "schemaVersion": 1,
          "id": "iphone-17",
          "displayName": "iPhone 17",
          "matches": {
            "simulatorDeviceTypes": ["com.apple.CoreSimulator.SimDeviceType.iPhone-17"],
            "deviceNames": ["iPhone 17"]
          },
          "asset": {"file": "device.usdz", "downloadURL": null, "sha256": null},
          "scene": {
            "rootNode": "root",
            "screenNode": null,
            "screenMaterial": "ScreenMaterial",
            "nativeOrientation": "portrait",
            "textureSize": {"width": 1206, "height": 2622},
            "usesScreenOverlay": false
          },
          "variantSets": []
        }
        """#
        let model = InstalledDeviceModel(
            definition: try DeviceModelDefinition.parsing(json: Data(json.utf8)),
            directoryURL: URL(fileURLWithPath: "/tmp/phone")
        )
        #expect(model.definition.scene.fold == nil)
        return model
    }

    final class Stage: @unchecked Sendable {
        let scene = MockDeviceScene()
        var built = 0
        var poses: [(Double, IntegratedPanel)] = []
        var cameras: [DeviceRotation] = []
        var composed: [FoldableScreens] = []
        var flat: [IOSurface] = []
        let output: IOSurface
        init() throws {
            output = try #require(RenderedScreenTests.surface(width: 8, height: 8))
            given(scene).update(hingeDegrees: .any, litPanel: .any).willProduce { [self] degrees, panel in
                self.poses.append((degrees, panel))
            }
            given(scene).update(camera: .any).willProduce { [self] camera in self.cameras.append(camera.rotation) }
            given(scene).render(screens: .any).willProduce { [self] screens in self.composed.append(screens); return self.output }
            given(scene).render(screen: .any).willProduce { [self] surface in self.flat.append(surface); return self.output }
        }
        func make(_ plan: DeviceRenderPlan) throws -> any DeviceScene {
            built += 1
            return scene
        }
    }

    @Test func `a foldable is posed at the hinge's angle with Core Device's panel and both frames`() async throws {
        let stage = try Stage()
        let snapshots = Device3DSnapshots(makeScene: stage.make)
        let inner = try #require(RenderedScreenTests.surface(width: 4, height: 6))
        let cover = try #require(RenderedScreenTests.surface(width: 3, height: 5))
        // 30° on the way shut: the unfolded panel is still lit. The angle
        // poses the book, Core Device names the panel; neither is read
        // off the other.
        let source = Device3DSnapshotSource(
            frames: { [.primary: cover, .secondary: inner] },
            hingeDegrees: { 30 },
            litPanel: { .secondary }
        )

        let shot = try await snapshots.snapshot(
            udid: "duo", model: try Self.duo(), request: .standard, source: source)

        #expect(shot.foldable)
        #expect(shot.hingeDegrees == 30)
        #expect(shot.litPanel == .secondary)
        #expect(!shot.png.isEmpty)
        #expect(stage.poses.map(\.0) == [30])
        #expect(stage.poses.map(\.1) == [.secondary])
        #expect(stage.composed.count == 1)
        #expect(stage.composed[0].unfolded === inner)
        #expect(stage.composed[0].cover === cover)
    }

    /// No reading is shown shut, as the device boots; no answer from
    /// Core Device is the cover — the same defaults the stream uses.
    @Test func `a silent hinge and a silent Core Device pose the book shut on the cover`() async throws {
        let stage = try Stage()
        let snapshots = Device3DSnapshots(makeScene: stage.make)
        let cover = try #require(RenderedScreenTests.surface(width: 3, height: 5))
        let source = Device3DSnapshotSource(
            frames: { [.primary: cover] }, hingeDegrees: { nil }, litPanel: { nil })

        let shot = try await snapshots.snapshot(
            udid: "duo", model: try Self.duo(), request: .standard, source: source)

        #expect(shot.hingeDegrees == nil)
        #expect(shot.litPanel == .primary)
        #expect(stage.poses.map(\.0) == [0])
        #expect(stage.poses.map(\.1) == [.primary])
        #expect(stage.composed[0].unfolded == nil)
        #expect(stage.composed[0].cover === cover)
    }

    @Test func `a phone renders its one frame flat, with no hinge or panel to report`() async throws {
        let stage = try Stage()
        let snapshots = Device3DSnapshots(makeScene: stage.make)
        let frame = try #require(RenderedScreenTests.surface(width: 3, height: 5))
        let source = Device3DSnapshotSource(
            frames: { [.primary: frame] }, hingeDegrees: { 130 }, litPanel: { .secondary })

        let shot = try await snapshots.snapshot(
            udid: "phone", model: try Self.phone(), request: .standard, source: source)

        #expect(!shot.foldable)
        #expect(shot.hingeDegrees == nil)
        #expect(shot.litPanel == nil)
        #expect(stage.poses.isEmpty)
        #expect(stage.flat.count == 1 && stage.flat[0] === frame)
    }

    /// Loading a model costs seconds; an agent asks every few seconds.
    @Test func `the scene is built once per device and canvas, and rotation is a camera move on it`() async throws {
        let stage = try Stage()
        let snapshots = Device3DSnapshots(makeScene: stage.make)
        let frame = try #require(RenderedScreenTests.surface(width: 3, height: 5))
        let source = Device3DSnapshotSource(
            frames: { [.primary: frame, .secondary: frame] }, hingeDegrees: { 130 }, litPanel: { .secondary })
        var turned = Device3DSnapshotRequest.standard
        turned.rotation = DeviceRotation(x: 0, y: 35, z: 0)
        var larger = Device3DSnapshotRequest.standard
        larger.outputSize = RenderDimensions(width: 512, height: 512)

        _ = try await snapshots.snapshot(udid: "duo", model: try Self.duo(), request: .standard, source: source)
        _ = try await snapshots.snapshot(udid: "duo", model: try Self.duo(), request: turned, source: source)
        #expect(stage.built == 1)
        #expect(stage.cameras == [.zero, DeviceRotation(x: 0, y: 35, z: 0)])

        _ = try await snapshots.snapshot(udid: "duo", model: try Self.duo(), request: larger, source: source)
        _ = try await snapshots.snapshot(udid: "other", model: try Self.duo(), request: .standard, source: source)
        #expect(stage.built == 3)

        snapshots.forget(udid: "duo")
        _ = try await snapshots.snapshot(udid: "duo", model: try Self.duo(), request: .standard, source: source)
        #expect(stage.built == 4)
    }

    @Test func `a frame that never arrives is a timeout, not a blank picture`() async throws {
        let stage = try Stage()
        let snapshots = Device3DSnapshots(makeScene: stage.make)
        let source = Device3DSnapshotSource(
            frames: { throw ScreenSnapshot.Failure.timeout }, hingeDegrees: { 130 }, litPanel: { .secondary })

        await #expect(throws: ScreenSnapshot.Failure.timeout) {
            try await snapshots.snapshot(udid: "duo", model: try Self.duo(), request: .standard, source: source)
        }
        #expect(stage.composed.isEmpty)
    }

    /// The production frame source: one delivery from the screen, every
    /// panel of a foldable at once, then the screen is stopped.
    @Test func `the live source takes one delivery and stops the screen`() async throws {
        let screen = MockScreen()
        let frame = try #require(RenderedScreenTests.surface(width: 3, height: 5))
        given(screen).start(onFrame: .any, onMetadata: .any).willProduce { onFrame, _ in
            onFrame(frame)
            onFrame(frame)
        }
        given(screen).stop().willReturn()

        let frames = try await Device3DSnapshotSource.firstFrames(of: screen, timeout: 1)

        #expect(frames.count == 1 && frames[.primary] === frame)
        verify(screen).stop().called(1)
    }

    @Test func `the live source gives up when the screen stays silent`() async throws {
        let screen = MockScreen()
        given(screen).start(onFrame: .any, onMetadata: .any).willReturn()
        given(screen).stop().willReturn()

        await #expect(throws: ScreenSnapshot.Failure.timeout) {
            try await Device3DSnapshotSource.firstFrames(of: screen, timeout: 0.05)
        }
        verify(screen).stop().called(1)
    }
}
