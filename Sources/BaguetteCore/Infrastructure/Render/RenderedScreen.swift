import Foundation
import IOSurface

/// A screen whose frames are composed through one persistent 3D device scene.
///
/// Rendering is serialized away from SimulatorKit's callback. At most one
/// pending surface is retained, so a slow model drops stale frames instead of
/// blocking capture or growing an unbounded queue.
final class RenderedScreen: Screen, @unchecked Sendable {
    private let source: any Screen
    private let scene: any DeviceScene
    private let lock = NSLock()
    private let queue = DispatchQueue(
        label: "com.baguette.rendered-screen",
        qos: .userInteractive
    )
    private var delivery: (@Sendable (IOSurface) -> Void)?
    private var isRendering = false
    private var pendingSurface: IOSurface?
    private var latestSurface: IOSurface?
    private var isStopped = true

    init(source: any Screen, scene: any DeviceScene) {
        self.source = source
        self.scene = scene
    }

    func start(onFrame: @escaping @Sendable (IOSurface) -> Void) throws {
        lock.withLock {
            delivery = onFrame
            isStopped = false
        }
        do {
            try source.start { [weak self] surface in
                self?.enqueue(surface)
            }
        } catch {
            lock.withLock {
                delivery = nil
                isStopped = true
            }
            throw error
        }
    }

    func stop() {
        lock.withLock {
            isStopped = true
            pendingSurface = nil
            latestSurface = nil
            delivery = nil
        }
        source.stop()
    }

    private func enqueue(_ surface: IOSurface) {
        let shouldStart = lock.withLock {
            guard !isStopped else { return false }
            latestSurface = surface
            if isRendering {
                pendingSurface = surface
                return false
            }
            isRendering = true
            return true
        }
        guard shouldStart else { return }
        queue.async { [weak self] in self?.render(surface) }
    }

    /// Recompose the retained simulator frame after an in-place pose change.
    func refresh() {
        guard let surface = lock.withLock({ isStopped ? nil : latestSurface }) else {
            return
        }
        enqueue(surface)
    }

    private func render(_ firstSurface: IOSurface) {
        var surface: IOSurface? = firstSurface
        while let current = surface {
            do {
                let rendered = try scene.render(screen: current)
                let callback = lock.withLock { isStopped ? nil : delivery }
                callback?(rendered)
            } catch {
                log("3D screen frame skipped: \(error)")
            }
            surface = lock.withLock {
                guard !isStopped, let pendingSurface else {
                    self.pendingSurface = nil
                    isRendering = false
                    return nil
                }
                self.pendingSurface = nil
                return pendingSurface
            }
        }
    }
}
