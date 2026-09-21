import Foundation
import IOSurface

/// One still of a simulator on its 3D device model, for an agent to look
/// at: the body, the hinge at the angle it is actually at, the panel it is
/// presenting on lit with its current frame.
struct Device3DSnapshot: Equatable, Sendable {
    let png: Data
    /// True when the model folds — the hinge and lit panel mean something.
    let foldable: Bool
    /// The hinge's reading as posed; nil on a phone, or when no reading
    /// arrived (the book is then shown shut, as the device boots).
    let hingeDegrees: Double?
    /// The panel Core Device says the device is presenting on; nil on a
    /// phone, `.primary` when it could not say.
    let litPanel: IntegratedPanel?
}

/// What a snapshot is asked for, beyond which device.
struct Device3DSnapshotRequest: Equatable, Sendable {
    var rotation: DeviceRotation = .zero
    /// The canvas. Square by default: a book stands landscape open and
    /// portrait shut, and an agent's picture should hold both.
    var outputSize = RenderDimensions(width: 1024, height: 1024)
    var background: DeviceRenderBackground = .transparent

    static let standard = Device3DSnapshotRequest()
}

/// What a snapshot reads off the device, behind a seam for tests: the
/// panels' current frames, the hinge angle, the lit panel.
struct Device3DSnapshotSource: Sendable {
    /// The latest frame of each panel, keyed by its Connected Screens
    /// name. A phone has one entry, `.primary`. Throws when no frame
    /// arrives in time.
    let frames: @Sendable () async throws -> [IntegratedPanel: IOSurface]
    let hingeDegrees: @Sendable () -> Double?
    let litPanel: @Sendable () -> IntegratedPanel?
}

/// Composes snapshots through scenes it keeps warm. Loading a USDZ and
/// standing the stage up costs seconds; an agent asks for a look every
/// few seconds, so one scene per device (per canvas) stays loaded and
/// each shot only paints, poses and renders. Rotation is a camera move
/// on the standing scene, not a rebuild.
final class Device3DSnapshots: @unchecked Sendable {
    static let shared = Device3DSnapshots()

    /// A scene is keyed by everything `RealityKitDeviceScene` fixes at
    /// build: the model, the canvas, the background.
    private struct Key: Hashable {
        let udid: String
        let model: DeviceModelID
        let width: Int
        let height: Int
        let background: String
    }

    private let lock = NSLock()
    private var scenes: [Key: (scene: any DeviceScene, usedAt: Date)] = [:]
    private let makeScene: (DeviceRenderPlan) throws -> any DeviceScene
    /// How many warm scenes to keep before the least recently used goes;
    /// each holds a Metal target ring and a loaded model.
    static let warmSceneLimit = 4

    init(makeScene: @escaping (DeviceRenderPlan) throws -> any DeviceScene = { plan in
        try RealityKitDeviceScene(plan: plan)
    }) {
        self.makeScene = makeScene
    }

    func snapshot(
        udid: String,
        model: InstalledDeviceModel,
        request: Device3DSnapshotRequest,
        source: Device3DSnapshotSource
    ) async throws -> Device3DSnapshot {
        let scene = try scene(udid: udid, model: model, request: request)
        let foldable = model.definition.scene.fold != nil
        // Read the device before the frames: the pose is what the hinge
        // said a moment before the picture, which is as close as a still
        // gets.
        let hinge = foldable ? source.hingeDegrees() : nil
        let lit = foldable ? (source.litPanel() ?? .primary) : nil
        let frames = try await source.frames()
        scene.update(camera: Device3DCamera(rotation: request.rotation, zoom: 1))
        let rendered: IOSurface
        if foldable {
            scene.update(hingeDegrees: hinge ?? 0, litPanel: lit ?? .primary)
            rendered = try scene.render(screens: FoldableScreens(
                unfolded: frames[.secondary], cover: frames[.primary]
            ))
        } else {
            guard let frame = frames[.primary] ?? frames.values.first else {
                throw ScreenSnapshot.Failure.timeout
            }
            rendered = try scene.render(screen: frame)
        }
        return Device3DSnapshot(
            png: try RealityKitDeviceRenderer.png(from: rendered),
            foldable: foldable,
            hingeDegrees: hinge,
            litPanel: lit
        )
    }

    /// Drops every warm scene (a device was shut down or deleted; tests).
    func forget(udid: String) {
        lock.lock()
        scenes = scenes.filter { $0.key.udid != udid }
        lock.unlock()
    }

    private func scene(
        udid: String, model: InstalledDeviceModel, request: Device3DSnapshotRequest
    ) throws -> any DeviceScene {
        let key = Key(
            udid: udid, model: model.definition.id,
            width: request.outputSize.width, height: request.outputSize.height,
            background: Self.name(request.background)
        )
        lock.lock()
        if let warm = scenes[key] {
            scenes[key] = (warm.scene, Date())
            lock.unlock()
            return warm.scene
        }
        lock.unlock()
        // Built outside the lock — seconds — then raced fairly: the
        // first to finish is kept, a duplicate is let go.
        let plan = try DeviceRenderPlan.build(
            model: model, variants: [:], rotation: request.rotation,
            outputSize: request.outputSize, background: request.background
        )
        let built = try makeScene(plan)
        lock.lock()
        defer { lock.unlock() }
        if let warm = scenes[key] { return warm.scene }
        scenes[key] = (built, Date())
        while scenes.count > Self.warmSceneLimit,
              let oldest = scenes.min(by: { $0.value.usedAt < $1.value.usedAt }) {
            scenes.removeValue(forKey: oldest.key)
        }
        return built
    }

    private static func name(_ background: DeviceRenderBackground) -> String {
        switch background {
        case .transparent: return "transparent"
        case .color(let hex): return hex
        }
    }
}

extension Device3DSnapshotSource {
    /// The production source: a `SimulatorKitScreen` opened for one
    /// delivery — every panel of a foldable at once — the shared hinge,
    /// and Core Device's lit panel.
    static func live(simulator: any Simulator, timeout: TimeInterval = 3) -> Device3DSnapshotSource {
        Device3DSnapshotSource(
            frames: { try await Self.firstFrames(of: simulator.screen(), timeout: timeout) },
            hingeDegrees: { simulator.hinge().angle()?.degrees },
            litPanel: { simulator.litPanel() }
        )
    }

    /// One delivery from `screen`, then stop. A foldable's screen hands
    /// its panels over together through `onPanels`; anything else
    /// delivers the one frame.
    static func firstFrames(of screen: any Screen, timeout: TimeInterval) async throws -> [IntegratedPanel: IOSurface] {
        let once = FirstDelivery()
        defer { screen.stop() }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[IntegratedPanel: IOSurface], Error>) in
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                guard once.claim() else { return }
                cont.resume(throwing: ScreenSnapshot.Failure.timeout)
            }
            timer.resume()
            (screen as? SimulatorKitScreen)?.onPanels = { surfaces, _ in
                guard once.claim() else { return }
                timer.cancel()
                var frames: [IntegratedPanel: IOSurface] = [:]
                for entry in surfaces { frames[entry.name] = entry.surface }
                cont.resume(returning: frames)
            }
            do {
                try screen.start(
                    onFrame: { surface in
                        guard once.claim() else { return }
                        timer.cancel()
                        cont.resume(returning: [.primary: surface])
                    },
                    onMetadata: { _ in }
                )
            } catch {
                guard once.claim() else { return }
                timer.cancel()
                cont.resume(throwing: error)
            }
        }
    }

    private final class FirstDelivery: @unchecked Sendable {
        private let lock = NSLock()
        private var taken = false
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if taken { return false }
            taken = true
            return true
        }
    }
}
