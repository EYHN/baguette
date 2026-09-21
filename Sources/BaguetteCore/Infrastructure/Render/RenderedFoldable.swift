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
///
/// Which panel is lit is `litPanel`'s call (Core Device's, through
/// `ActiveDisplays`), never the angle's. It is asked on every hinge
/// sample and before every composition — a cached read while the
/// device is followed — so a panel that lights without the hinge
/// moving (the pose provider taking its time, an app claiming the
/// cover) re-poses the book on the next frame either panel delivers.
final class RenderedFoldable: Screen, @unchecked Sendable {
    private let unfolded: any Screen
    private let cover: any Screen
    private let hinge: any Hinge
    private let litPanel: @Sendable () -> IntegratedPanel
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
    /// A scene starts flat. Nothing is composed until the book has been
    /// posed, or the first frame would show it open when shut.
    private var isPosed = false
    /// The hinge's own angle, as last heard (shut until it speaks).
    private var hingeDegrees: Double = 0
    /// The lit panel as last posed.
    private var posedPanel: IntegratedPanel = .primary

    /// The pose the book is shown at.
    var pose: FoldablePose {
        lock.withLock { FoldablePose(hingeDegrees: hingeDegrees) }
    }

    private let onPose: @Sendable () -> Void

    /// `litPanel` says which panel the device presents on; `onPose`
    /// runs after each hinge sample or panel change has posed the scene.
    init(
        unfolded: any Screen, cover: any Screen, hinge: any Hinge,
        litPanel: @escaping @Sendable () -> IntegratedPanel,
        scene: any DeviceScene,
        onPose: @escaping @Sendable () -> Void = {}
    ) {
        self.unfolded = unfolded
        self.cover = cover
        self.hinge = hinge
        self.litPanel = litPanel
        self.scene = scene
        self.onPose = onPose
    }

    func start(
        onFrame: @escaping @Sendable (IOSurface) -> Void,
        onMetadata: @escaping @Sendable (ScreenMetadata) -> Void
    ) throws {
        lock.withLock {
            delivery = onFrame
            isStopped = false
            isPosed = false
        }
        // A silent hinge (the guest's motion stream can drop) still
        // gets a book: shut, as the device boots, until it speaks.
        let standing = hinge.angle()?.degrees ?? 0
        let lit = litPanel()
        lock.withLock {
            hingeDegrees = standing
            posedPanel = lit
            isPosed = true
        }
        scene.update(hingeDegrees: standing, litPanel: lit)
        // Rendering decorates pixels only; the screen properties that
        // pass through are the lit panel's — the one the guest drives.
        let litPanel = self.litPanel
        do {
            try unfolded.start(
                onFrame: { [weak self] surface in
                    self?.take { FoldableScreens(unfolded: surface, cover: $0.cover) }
                },
                onMetadata: { metadata in
                    if litPanel() == .secondary { onMetadata(metadata) }
                }
            )
            try cover.start(
                onFrame: { [weak self] surface in
                    self?.take { FoldableScreens(unfolded: $0.unfolded, cover: surface) }
                },
                onMetadata: { metadata in
                    if litPanel() == .primary { onMetadata(metadata) }
                }
            )
        } catch {
            stop()
            throw error
        }
        let watch = hinge.watch { [weak self] angle in
            guard let self else { return }
            let lit = self.litPanel()
            self.lock.withLock {
                self.hingeDegrees = angle.degrees
                self.posedPanel = lit
                self.isPosed = true
            }
            self.scene.update(hingeDegrees: angle.degrees, litPanel: lit)
            self.onPose()
            self.refresh()
        }
        lock.withLock { self.watch = watch }
    }

    /// The lit panel moved without the hinge (or Core Device answered
    /// after the sweep): re-pose before the next composition.
    private func followPanel() {
        let lit = litPanel()
        let repose: Double? = lock.withLock {
            guard isPosed, lit != posedPanel else { return nil }
            posedPanel = lit
            return hingeDegrees
        }
        guard let degrees = repose else { return }
        scene.update(hingeDegrees: degrees, litPanel: lit)
        onPose()
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
            guard isPosed, latest.unfolded != nil || latest.cover != nil else { return false }
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
            followPanel()
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
