import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// One monitor per device. Every stream socket on a foldable wants the
/// sweep and every bind wants the current angle; spawning a devicectl
/// per caller put several monitors on one device at once and a fresh
/// spawn on every resolve. `SharedHinge` runs a single inner watch,
/// fans its samples out, and answers `angle()` from the last sample
/// while it runs.
@Suite("SharedHinge")
struct SharedHingeTests {

    final class Inner: @unchecked Sendable {
        let hinge = MockHinge()
        let watch = MockHingeWatch()
        var onAngle: (@Sendable (HingeAngle) -> Void)?
        var onEnd: (@Sendable () -> Void)?
        var watches = 0
        init() {
            given(hinge).watch(onAngle: .any, onEnd: .any).willProduce { [self] cb, end in
                self.onAngle = cb
                self.onEnd = end
                self.watches += 1
                return self.watch
            }
            given(watch).cancel().willReturn()
        }
    }

    final class Seen: @unchecked Sendable { var angles: [Double] = [] }

    /// Restarts run on demand: the test decides when the delay is over.
    final class Scheduler: @unchecked Sendable {
        var pending: [(delay: TimeInterval, item: DispatchWorkItem)] = []
        func schedule(_ delay: TimeInterval, _ work: @escaping @Sendable () -> Void) -> DispatchWorkItem {
            let item = DispatchWorkItem(block: work)
            pending.append((delay, item))
            return item
        }
        func runAll() {
            let due = pending
            pending = []
            for (_, item) in due where !item.isCancelled { item.perform() }
        }
    }

    @Test func `subscribers share one inner watch and all receive each sample`() {
        let inner = Inner()
        let shared = SharedHinge(inner: inner.hinge)
        let a = Seen(), b = Seen()
        let wa = shared.watch { a.angles.append($0.degrees) }
        let wb = shared.watch { b.angles.append($0.degrees) }
        inner.onAngle?(HingeAngle(degrees: 3.8))
        inner.onAngle?(HingeAngle(degrees: 57))
        #expect(inner.watches == 1)
        #expect(a.angles == [3.8, 57])
        #expect(b.angles == [3.8, 57])
        wa.cancel(); wb.cancel()
    }

    @Test func `a watcher joining a running monitor is told the standing angle at once`() {
        // devicectl reports a change-driven stream: the standing angle
        // comes once, at start. A socket that joins later — a 3D scene
        // opened while the page's own socket already watches — would
        // otherwise wait for the hinge to move before it could pose.
        let inner = Inner()
        let shared = SharedHinge(inner: inner.hinge)
        let first = shared.watch { _ in }
        inner.onAngle?(HingeAngle(degrees: 130))
        let late = Seen()
        let w = shared.watch { late.angles.append($0.degrees) }
        #expect(late.angles == [130])
        inner.onAngle?(HingeAngle(degrees: 120))
        #expect(late.angles == [130, 120])
        w.cancel(); first.cancel()
    }

    @Test func `while watched, the angle is the last sample with no read`() {
        let inner = Inner()
        let shared = SharedHinge(inner: inner.hinge)
        let w = shared.watch { _ in }
        inner.onAngle?(HingeAngle(degrees: 130))
        #expect(shared.angle() == HingeAngle(degrees: 130))
        verify(inner.hinge).angle().called(0)
        w.cancel()
    }

    @Test func `with no watch running, the angle is read`() {
        let inner = Inner()
        given(inner.hinge).angle().willReturn(HingeAngle(degrees: 0))
        let shared = SharedHinge(inner: inner.hinge)
        #expect(shared.angle() == HingeAngle(degrees: 0))
        verify(inner.hinge).angle().called(1)
    }

    /// Before the monitor's first sample lands there is nothing cached;
    /// a read answers rather than a stale `nil`.
    @Test func `a watch that has not sampled yet does not shadow a read`() {
        let inner = Inner()
        given(inner.hinge).angle().willReturn(HingeAngle(degrees: 180))
        let shared = SharedHinge(inner: inner.hinge)
        let w = shared.watch { _ in }
        #expect(shared.angle() == HingeAngle(degrees: 180))
        w.cancel()
    }

    @Test func `the inner watch stops when the last subscriber leaves, not before`() {
        let inner = Inner()
        let shared = SharedHinge(inner: inner.hinge)
        let wa = shared.watch { _ in }
        let wb = shared.watch { _ in }
        wa.cancel()
        verify(inner.watch).cancel().called(0)
        wb.cancel()
        verify(inner.watch).cancel().called(1)
    }

    @Test func `a cancelled subscriber receives nothing more`() {
        let inner = Inner()
        let shared = SharedHinge(inner: inner.hinge)
        let a = Seen()
        let wa = shared.watch { a.angles.append($0.degrees) }
        let wb = shared.watch { _ in }
        wa.cancel()
        inner.onAngle?(HingeAngle(degrees: 90))
        #expect(a.angles.isEmpty)
        wb.cancel()
    }

    /// A pose change ends with the page reloading, which closes the
    /// socket — and so the watch — a moment before the new page's
    /// definition, mask and stream requests each ask the angle. Those
    /// must agree, and the sweep's last sample is the truth for a
    /// while: the hinge does not move without Device Hub, and the new
    /// page's socket restarts the watch within seconds.
    @Test func `the last sample outlives the watch for a grace period`() {
        let inner = Inner()
        var now = Date(timeIntervalSince1970: 1000)
        let shared = SharedHinge(inner: inner.hinge, now: { now })
        let w = shared.watch { _ in }
        inner.onAngle?(HingeAngle(degrees: 4.8))
        w.cancel()
        now = now.addingTimeInterval(3)
        #expect(shared.angle() == HingeAngle(degrees: 4.8))
        verify(inner.hinge).angle().called(0)
    }

    @Test func `after the grace period the angle is read again`() {
        let inner = Inner()
        given(inner.hinge).angle().willReturn(HingeAngle(degrees: 130))
        var now = Date(timeIntervalSince1970: 1000)
        let shared = SharedHinge(inner: inner.hinge, now: { now })
        let w = shared.watch { _ in }
        inner.onAngle?(HingeAngle(degrees: 4.8))
        w.cancel()
        now = now.addingTimeInterval(SharedHinge.gracePeriod + 1)
        #expect(shared.angle() == HingeAngle(degrees: 130))
    }

    /// A page reload asks the angle from several requests at once —
    /// `/hinge`, the definition, the stream bind — before any socket
    /// has restarted the watch. Each spawning its own monitor is what
    /// produced disagreeing panels (a second concurrent devicectl
    /// monitor answers 0° for a device sitting at 130°). One read
    /// serves the burst: the first spawns, the rest share its sample.
    @Test func `a one-shot read is remembered for the grace period`() {
        let inner = Inner()
        given(inner.hinge).angle().willReturn(HingeAngle(degrees: 130))
        var now = Date(timeIntervalSince1970: 1000)
        let shared = SharedHinge(inner: inner.hinge, now: { now })
        #expect(shared.angle() == HingeAngle(degrees: 130))
        now = now.addingTimeInterval(2)
        #expect(shared.angle() == HingeAngle(degrees: 130))
        verify(inner.hinge).angle().called(1)
    }

    /// A failed read is not remembered — the next caller tries again.
    @Test func `a read that returns nothing is not cached as an angle, but is not retried at once`() {
        // A silent hinge (the guest's motion stream can drop after a
        // SpringBoard restart) makes every read wait out its deadline;
        // callers queue behind the serialised read and the server
        // stalls. The silence is remembered for a short while instead.
        var clock = Date(timeIntervalSince1970: 1_000)
        let inner = Inner()
        given(inner.hinge).angle().willReturn(nil)
        let shared = SharedHinge(inner: inner.hinge, now: { clock })
        #expect(shared.angle() == nil)
        #expect(shared.angle() == nil)
        verify(inner.hinge).angle().called(1)
        clock = clock.addingTimeInterval(SharedHinge.silencePeriod + 0.1)
        #expect(shared.angle() == nil)
        verify(inner.hinge).angle().called(2)
    }

    @Test func `folding sweeps from the angle last heard to the one asked for`() throws {
        let inner = Inner()
        let motor = MockHingeMotor()
        given(motor).fold(from: .any, to: .any, over: .any).willReturn()
        let shared = SharedHinge(inner: inner.hinge, motor: motor)
        let w = shared.watch { _ in }
        inner.onAngle?(HingeAngle(degrees: 130))

        try shared.fold(to: 0, over: 0.8)

        verify(motor).fold(from: .value(130), to: .value(0), over: .value(0.8)).called(1)
        w.cancel()
    }

    @Test func `with no angle heard, a fold starts from shut`() throws {
        let inner = Inner()
        given(inner.hinge).angle().willReturn(nil)
        let motor = MockHingeMotor()
        given(motor).fold(from: .any, to: .any, over: .any).willReturn()
        let shared = SharedHinge(inner: inner.hinge, motor: motor)

        try shared.fold(to: 130, over: 0.8)

        verify(motor).fold(from: .value(0), to: .value(130), over: .value(0.8)).called(1)
    }

    // MARK: - the monitor dies

    /// A devicectl monitor that was killed (or crashed, or timed out)
    /// once left `angle()` answering its last sample for the rest of
    /// the process — the watch was still "running" as far as the
    /// bookkeeping knew. An ended watch is forgotten at once.
    @Test func `when the monitor ends, the angle is no longer its last sample`() {
        let inner = Inner()
        given(inner.hinge).angle().willReturn(HingeAngle(degrees: 120))
        var now = Date(timeIntervalSince1970: 1000)
        let scheduler = Scheduler()
        let shared = SharedHinge(inner: inner.hinge, now: { now }, schedule: scheduler.schedule)
        let w = shared.watch { _ in }
        inner.onAngle?(HingeAngle(degrees: 22))
        inner.onEnd?()
        now = now.addingTimeInterval(SharedHinge.gracePeriod + 1)
        #expect(shared.angle() == HingeAngle(degrees: 120))
        verify(inner.hinge).angle().called(1)
        w.cancel()
    }

    @Test func `a monitor that ends after speaking is started again at once for its subscribers`() {
        let inner = Inner()
        let scheduler = Scheduler()
        let shared = SharedHinge(inner: inner.hinge, schedule: scheduler.schedule)
        let seen = Seen()
        let w = shared.watch { seen.angles.append($0.degrees) }
        inner.onAngle?(HingeAngle(degrees: 22))
        inner.onEnd?()
        #expect(scheduler.pending.map(\.delay) == [0])
        scheduler.runAll()
        #expect(inner.watches == 2)
        inner.onAngle?(HingeAngle(degrees: 95))
        #expect(seen.angles == [22, 95])
        #expect(shared.angle() == HingeAngle(degrees: 95))
        w.cancel()
    }

    /// A device that is shut down, or has no hinge, makes devicectl
    /// quit at once with nothing said. Trying again forever at full
    /// speed would be a spawn storm; the pause grows instead.
    @Test func `a monitor that ends without speaking is retried after a growing pause`() {
        let inner = Inner()
        let scheduler = Scheduler()
        let shared = SharedHinge(inner: inner.hinge, schedule: scheduler.schedule)
        let w = shared.watch { _ in }
        var delays: [TimeInterval] = []
        for _ in 0..<8 {
            inner.onEnd?()
            delays.append(scheduler.pending.last!.delay)
            scheduler.runAll()
        }
        #expect(delays == [1, 2, 4, 8, 16, 32, 60, 60])
        #expect(inner.watches == 9)
        // Once it speaks, the slate is clean.
        inner.onAngle?(HingeAngle(degrees: 3))
        inner.onEnd?()
        #expect(scheduler.pending.last!.delay == 0)
        w.cancel()
    }

    @Test func `no restart is scheduled once the last subscriber has left`() {
        let inner = Inner()
        let scheduler = Scheduler()
        let shared = SharedHinge(inner: inner.hinge, schedule: scheduler.schedule)
        let w = shared.watch { _ in }
        inner.onEnd?()
        #expect(scheduler.pending.count == 1)
        w.cancel()
        #expect(scheduler.pending[0].item.isCancelled)
        scheduler.runAll()
        #expect(inner.watches == 1)
    }

    @Test func `an end reported by a replaced monitor changes nothing`() {
        let inner = Inner()
        let scheduler = Scheduler()
        let shared = SharedHinge(inner: inner.hinge, schedule: scheduler.schedule)
        let w = shared.watch { _ in }
        let staleEnd = inner.onEnd
        inner.onAngle?(HingeAngle(degrees: 22))
        inner.onEnd?()
        scheduler.runAll()
        #expect(inner.watches == 2)
        inner.onAngle?(HingeAngle(degrees: 40))
        staleEnd?()
        #expect(scheduler.pending.isEmpty)
        #expect(shared.angle() == HingeAngle(degrees: 40))
        w.cancel()
    }

    /// A foldable's hinge is followed for the life of the process, so
    /// its angle is always the last sample heard.
    @Test func `keepWatching holds one inner watch open with no other subscriber, once`() {
        let inner = Inner()
        let shared = SharedHinge(inner: inner.hinge)
        shared.keepWatching()
        shared.keepWatching()
        #expect(inner.watches == 1)
        inner.onAngle?(HingeAngle(degrees: 130))
        let w = shared.watch { _ in }
        w.cancel()
        verify(inner.watch).cancel().called(0)
        #expect(shared.angle() == HingeAngle(degrees: 130))
        verify(inner.hinge).angle().called(0)
    }

    /// The same device always gets the same shared hinge, whoever asks.
    @Test func `the registry hands out one shared hinge per device`() {
        let inner = Inner()
        let first = SharedHinge.forDevice("duo", make: { inner.hinge })
        let second = SharedHinge.forDevice("duo", make: { MockHinge() })
        #expect(first === second)
        #expect(SharedHinge.forDevice("other", make: { MockHinge() }) !== first)
    }
}
