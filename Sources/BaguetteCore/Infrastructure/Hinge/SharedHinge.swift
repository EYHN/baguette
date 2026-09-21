import Foundation

/// One monitor per device, shared by everyone who asks about its hinge.
///
/// A foldable's stream sockets each want the sweep, and every bind of
/// the phone plane wants the current angle. Giving each caller its own
/// `DevicectlHinge` put several monitors on one device at once and a
/// fresh spawn on every resolve — including inside `/hinge` polls
/// while a socket was already streaming samples. This runs a single
/// inner watch for as long as anyone subscribes, fans its samples out,
/// and answers `angle()` from the last sample while it runs; with no
/// watch running it falls back to a one-shot read.
///
/// The inner watch is not trusted to live: `devicectl` is a child that
/// can be killed, crash, or run out its timeout, and a monitor that
/// died silently once left every caller reading the angle it last
/// heard for the rest of the process. When the inner watch ends while
/// anyone still subscribes, it is started again — at once after it had
/// spoken, with a growing pause when it never did (a device that is
/// shut down, or has no hinge) — and until it is back the angle falls
/// through to the grace period and a one-shot read, as with no watch.
///
/// `keepWatching` is a subscriber that never leaves: a foldable's hinge
/// is followed for the life of the process, so its angle is always the
/// last sample and never a spawn away (see `CoreSimulator.hinge()`).
///
/// All of the bookkeeping — subscriber fan-out, last sample, start on
/// first / stop on last, restart — is here and unit-covered against
/// `MockHinge`; the inner hinge owns the process.
final class SharedHinge: Hinge, @unchecked Sendable {
    private let inner: any Hinge
    private let now: () -> Date
    private let lock = NSLock()
    private var subscribers: [UUID: @Sendable (HingeAngle) -> Void] = [:]
    private var innerWatch: (any HingeWatch)?
    private var last: (angle: HingeAngle, at: Date)?
    /// Whether the running inner watch has delivered a sample; decides
    /// how soon it is restarted when it ends.
    private var innerSpoke = false
    /// Consecutive inner watches that ended without a sample.
    private var silentEnds = 0
    private var restart: DispatchWorkItem?
    private var standing: (any HingeWatch)?
    private let schedule: (TimeInterval, @escaping @Sendable () -> Void) -> DispatchWorkItem

    /// How long to wait before starting the monitor again after it
    /// ended without a sample: doubling from the first, capped.
    static let restartDelays: (first: TimeInterval, cap: TimeInterval) = (1, 60)

    static func restartDelay(afterSilentEnds count: Int) -> TimeInterval {
        min(restartDelays.first * pow(2, Double(max(0, count - 1))), restartDelays.cap)
    }

    /// How long the last sample stays the answer after the watch
    /// stops. A pose change ends with the page reloading — socket and
    /// watch go down — and the new page's definition, mask and stream
    /// requests all ask within the next second or two. They must agree,
    /// and the sweep's final sample is the truth: the hinge does not
    /// move without Device Hub, and the new socket restarts the watch.
    static let gracePeriod: TimeInterval = 10

    private let motor: (any HingeMotor)?

    /// `schedule` runs a restart after a delay; the default is a global
    /// queue, tests hand in one that runs on demand.
    init(
        inner: any Hinge,
        motor: (any HingeMotor)? = nil,
        now: @escaping () -> Date = { Date() },
        schedule: @escaping (TimeInterval, @escaping @Sendable () -> Void) -> DispatchWorkItem = { delay, work in
            let item = DispatchWorkItem(block: work)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: item)
            return item
        }
    ) {
        self.inner = inner
        self.motor = motor
        self.now = now
        self.schedule = schedule
    }

    /// Follow the hinge for as long as this process lives. Idempotent.
    func keepWatching() {
        lock.lock()
        let already = standing != nil
        lock.unlock()
        guard !already else { return }
        let watch = self.watch { _ in }
        lock.lock()
        if standing == nil {
            standing = watch
            lock.unlock()
        } else {
            lock.unlock()
            watch.cancel()
        }
    }

    /// A sweep starts where the hinge is — the angle last heard, or shut
    /// when nothing has been heard, as the device boots.
    func fold(to degrees: Double, over duration: TimeInterval) throws {
        guard let motor else { throw HingeError.toolMissing }
        let from = angle()?.degrees ?? 0
        try motor.fold(from: from, to: degrees, over: duration)
    }

    // MARK: - registry

    nonisolated(unsafe) private static var registry: [String: SharedHinge] = [:]
    private static let registryLock = NSLock()

    /// The shared hinge for `udid`, made on first use.
    static func forDevice(
        _ udid: String, make: () -> any Hinge, motor: @autoclosure () -> (any HingeMotor)? = nil
    ) -> SharedHinge {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = registry[udid] { return existing }
        let made = SharedHinge(inner: make(), motor: motor())
        registry[udid] = made
        return made
    }

    // MARK: - Hinge

    /// Serialises one-shot reads: a burst of callers with nothing
    /// cached spawns one monitor, and the rest take its sample. Two
    /// concurrent devicectl monitors on one device do not agree — the
    /// second reported 0° for a device at 130° — which is how a reload
    /// once bound the unfolded panel's stream under the cover's chrome.
    private let readLock = NSLock()

    /// How long a silent hinge is taken at its word. A read that heard
    /// nothing waited out its deadline; asking again at once would make
    /// every caller queue behind another such wait, and the server
    /// would stall for as long as the guest's motion stream is down.
    static let silencePeriod: TimeInterval = 3
    private var silentSince: Date?

    func angle() -> HingeAngle? {
        if let cached = fresh() { return cached }
        readLock.lock()
        defer { readLock.unlock() }
        if let cached = fresh() { return cached }
        lock.lock()
        let silent = silentSince.map { now().timeIntervalSince($0) < Self.silencePeriod } ?? false
        lock.unlock()
        if silent { return nil }
        guard let read = inner.angle() else {
            lock.lock()
            silentSince = now()
            lock.unlock()
            return nil
        }
        lock.lock()
        last = (read, now())
        silentSince = nil
        lock.unlock()
        return read
    }

    private func fresh() -> HingeAngle? {
        lock.lock()
        defer { lock.unlock() }
        guard let cached = last else { return nil }
        if innerWatch != nil || now().timeIntervalSince(cached.at) <= Self.gracePeriod {
            return cached.angle
        }
        return nil
    }

    func watch(
        onAngle: @escaping @Sendable (HingeAngle) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) -> any HingeWatch {
        // A shared watch never ends on its subscribers: an inner watch
        // that stops is started again for as long as they stay.
        _ = onEnd
        let id = UUID()
        lock.lock()
        subscribers[id] = onAngle
        let startInner = run == nil && restart == nil
        // The stream is change-driven: its standing angle came once, at
        // start. A watcher joining a running monitor gets it now.
        let known = startInner ? nil : last?.angle
        lock.unlock()
        if let known { onAngle(known) }
        if startInner { startInnerWatch() }
        return Subscription { [weak self] in self?.remove(id) }
    }

    /// One run of the monitor. Samples and the end are attributed to
    /// the run that produced them, so a run that has been replaced or
    /// cancelled changes nothing when it speaks late.
    private final class Run: @unchecked Sendable {
        var watch: (any HingeWatch)?
        var ended = false
    }
    private var run: Run?

    private func startInnerWatch() {
        let run = Run()
        lock.lock()
        self.run = run
        innerSpoke = false
        lock.unlock()
        let started = inner.watch(
            onAngle: { [weak self] angle in self?.deliver(angle, from: run) },
            onEnd: { [weak self] in self?.innerEnded(run) }
        )
        lock.lock()
        guard self.run === run else {
            // Nobody wants it any more (the last subscriber left while
            // the monitor was spawning).
            lock.unlock()
            started.cancel()
            return
        }
        run.watch = started
        if run.ended {
            // It ended before we could register it: treat as an end now.
            lock.unlock()
            innerEnded(run, registered: true)
            return
        }
        innerWatch = started
        lock.unlock()
    }

    private func deliver(_ angle: HingeAngle, from run: Run) {
        lock.lock()
        guard self.run === run else {
            lock.unlock()
            return
        }
        last = (angle, now())
        innerSpoke = true
        silentEnds = 0
        let targets = Array(subscribers.values)
        lock.unlock()
        for target in targets { target(angle) }
    }

    /// The monitor stopped without being asked to. Forget it — the
    /// angle is answered by grace period and one-shot read meanwhile —
    /// and, if anyone still listens, bring it back.
    private func innerEnded(_ run: Run, registered: Bool = false) {
        lock.lock()
        guard self.run === run else {
            lock.unlock()
            return
        }
        run.ended = true
        guard registered || run.watch != nil else {
            // `startInnerWatch` has not registered it yet; it will see
            // `ended` and come back here.
            lock.unlock()
            return
        }
        self.run = nil
        innerWatch = nil
        let spoke = innerSpoke
        if !spoke { silentEnds += 1 }
        let delay = spoke ? 0 : Self.restartDelay(afterSilentEnds: silentEnds)
        restart?.cancel()
        restart = nil
        if !subscribers.isEmpty {
            restart = schedule(delay) { [weak self] in self?.restartInner() }
        }
        lock.unlock()
    }

    private func restartInner() {
        lock.lock()
        restart = nil
        let start = run == nil && !subscribers.isEmpty
        lock.unlock()
        if start { startInnerWatch() }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        subscribers[id] = nil
        var stop: (any HingeWatch)?
        var pending: DispatchWorkItem?
        if subscribers.isEmpty {
            stop = innerWatch
            innerWatch = nil
            run = nil
            pending = restart
            restart = nil
        }
        lock.unlock()
        stop?.cancel()
        pending?.cancel()
    }

    private final class Subscription: HingeWatch, @unchecked Sendable {
        private let lock = NSLock()
        private var onCancel: (() -> Void)?
        init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }
        func cancel() {
            lock.lock()
            let run = onCancel
            onCancel = nil
            lock.unlock()
            run?()
        }
    }
}
