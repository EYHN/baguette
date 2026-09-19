import Foundation
import IOSurface

/// A foldable's two screens and hinge, composed through one persistent
/// 3D device scene.
///
/// Frames from either panel and hinge samples all funnel into one
/// serialized composition of the latest state — the latest frame of
/// each panel on its screen, the book posed at the latest angle. As in
/// `RenderedScreen`, at most one composition is pending, so a slow model
/// drops stale work instead of queueing it.
final class RenderedFoldable: Screen, @unchecked Sendable {
    private let unfolded: any Screen
    private let cover: any Screen
    private let hinge: any Hinge
    private let scene: any DeviceScene
    private let lock = NSLock()
    private let queue = DispatchQueue(
        label: "com.baguette.rendered-foldable",
        qos: .userInteractive
    )
    private var delivery: (@Sendable (IOSurface) -> Void)?
    private var watch: (any HingeWatch)?
    private var isRendering = false
    private var pending = false
    private var latest = FoldableScreens(unfolded: nil, cover: nil)
    private var isStopped = true

    init(unfolded: any Screen, cover: any Screen, hinge: any Hinge, scene: any DeviceScene) {
        self.unfolded = unfolded
        self.cover = cover
        self.hinge = hinge
        self.scene = scene
    }

    func start(onFrame: @escaping @Sendable (IOSurface) -> Void) throws {
        lock.withLock {
            delivery = onFrame
            isStopped = false
        }
        do {
            try unfolded.start { [weak self] surface in
                self?.take { FoldableScreens(unfolded: surface, cover: $0.cover) }
            }
            try cover.start { [weak self] surface in
                self?.take { FoldableScreens(unfolded: $0.unfolded, cover: surface) }
            }
        } catch {
            stop()
            throw error
        }
        let watch = hinge.watch { [weak self] angle in
            guard let self else { return }
            self.scene.update(hingeDegrees: angle.degrees)
            self.refresh()
        }
        lock.withLock { self.watch = watch }
    }

    func stop() {
        let watch = lock.withLock {
            isStopped = true
            pending = false
            latest = FoldableScreens(unfolded: nil, cover: nil)
            delivery = nil
            defer { self.watch = nil }
            return self.watch
        }
        watch?.cancel()
        unfolded.stop()
        cover.stop()
    }

    /// Recompose the retained frames after a pose or camera change.
    func refresh() {
        take { $0 }
    }

    private func take(_ update: (FoldableScreens) -> FoldableScreens) {
        let shouldStart = lock.withLock {
            guard !isStopped else { return false }
            latest = update(latest)
            guard latest.unfolded != nil || latest.cover != nil else { return false }
            if isRendering {
                pending = true
                return false
            }
            isRendering = true
            return true
        }
        guard shouldStart else { return }
        queue.async { [weak self] in self?.render() }
    }

    private func render() {
        while true {
            let screens = lock.withLock { latest }
            do {
                let rendered = try scene.render(screens: screens)
                let callback = lock.withLock { isStopped ? nil : delivery }
                callback?(rendered)
            } catch {
                log("3D foldable frame skipped: \(error)")
            }
            let again = lock.withLock {
                guard !isStopped, pending else {
                    pending = false
                    isRendering = false
                    return false
                }
                pending = false
                return true
            }
            if !again { return }
        }
    }
}
