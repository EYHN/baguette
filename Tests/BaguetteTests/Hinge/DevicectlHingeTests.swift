import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// `DevicectlHinge` reads one sample from `xcrun devicectl device motion
/// hinge-angle` and stops. The monitor is a stream that runs until its
/// timeout, so the orchestration is: spawn, split lines, take the first
/// sample, terminate — and give up on exit or after a deadline. All of
/// that is driven here through `MockSubprocess`; the `Foundation.Process`
/// plumbing is integration-only.
@Suite("DevicectlHinge — orchestration via Subprocess")
struct DevicectlHingeTests {

    final class Captures: @unchecked Sendable {
        var executable: URL?
        var arguments: [String]?
        var onBytes: (@Sendable (Data) -> Void)?
        var onExit: (@Sendable (Int32) -> Void)?
    }

    private let sample = "• +0.000s : Angle:130.0°  Mech:130.0°  Velocity:+0.0°/s  AngleValid:Y  VelocityValid:N  Range:0-180°\n"
    private let banner = "Hinge angle monitoring started. 60 seconds remaining:\n"

    /// `feed` runs inside the spawn, before `angle()` starts waiting —
    /// which is how a real child that answers instantly behaves too.
    private func makeHinge(
        feed: @escaping @Sendable (Captures) -> Void
    ) -> (DevicectlHinge, MockSubprocess, Captures) {
        let sub = MockSubprocess()
        let captures = Captures()
        given(sub).run(
            executable: .any, arguments: .any, onBytes: .any, onExit: .any
        ).willProduce { exe, args, onBytes, onExit in
            captures.executable = exe
            captures.arguments = args
            captures.onBytes = onBytes
            captures.onExit = onExit
            feed(captures)
        }
        given(sub).terminate().willReturn()
        let hinge = DevicectlHinge(udid: "duo", subprocess: { sub }, deadline: 0.5)
        return (hinge, sub, captures)
    }

    @Test func `asks devicectl to monitor this device's hinge`() {
        let (hinge, _, captures) = makeHinge { c in c.onBytes?(Data(self.sample.utf8)) }
        _ = hinge.angle()
        #expect(captures.executable?.path == "/usr/bin/xcrun")
        #expect(captures.arguments?.prefix(4) == ["devicectl", "device", "motion", "hinge-angle"])
        #expect(captures.arguments?.contains("duo") == true)
    }

    @Test func `the first sample is the reading`() {
        let (hinge, _, _) = makeHinge { c in c.onBytes?(Data((self.banner + self.sample).utf8)) }
        #expect(hinge.angle() == HingeAngle(degrees: 130))
    }

    /// The monitor keeps streaming until its own timeout; one sample is
    /// all that is needed, so the child is stopped as soon as it lands.
    @Test func `the monitor is terminated once a sample has landed`() {
        let (hinge, sub, _) = makeHinge { c in c.onBytes?(Data(self.sample.utf8)) }
        _ = hinge.angle()
        verify(sub).terminate().called(1)
    }

    /// Output arrives in whatever chunks the pipe delivers; a sample
    /// split across two of them is still one sample.
    @Test func `a sample split across chunks is reassembled`() {
        let head = String(sample.prefix(30))
        let tail = String(sample.dropFirst(30))
        let (hinge, _, _) = makeHinge { c in
            c.onBytes?(Data(head.utf8))
            c.onBytes?(Data(tail.utf8))
        }
        #expect(hinge.angle() == HingeAngle(degrees: 130))
    }

    /// A device without a hinge makes devicectl print an error and exit;
    /// that is "no reading", not a crash and not a stale number.
    @Test func `an exit before any sample is no reading`() {
        let (hinge, _, _) = makeHinge { c in
            c.onBytes?(Data("Error: Hinge angle monitoring is not available on this device.\n".utf8))
            c.onExit?(1)
        }
        #expect(hinge.angle() == nil)
    }

    /// A child that never answers must not hang the caller — this sits
    /// on the path that binds every screen and input on a foldable.
    @Test func `a silent monitor times out to no reading and is stopped`() {
        let (hinge, sub, _) = makeHinge { _ in }
        #expect(hinge.angle() == nil)
        verify(sub).terminate().called(1)
    }

    @Test func `a spawn failure is no reading`() {
        let sub = MockSubprocess()
        given(sub).run(
            executable: .any, arguments: .any, onBytes: .any, onExit: .any
        ).willThrow(NSError(domain: "spawn", code: 1))
        let hinge = DevicectlHinge(udid: "duo", subprocess: { sub }, deadline: 0.5)
        #expect(hinge.angle() == nil)
    }

    // MARK: - watch

    /// Device Hub animates a pose change as a 0.5–0.85 s sweep of
    /// samples at 60 Hz (measured: 3.8° → 130° in 0.84 s, ease-out).
    /// A watch hands every sample on, in order, for as long as it runs.
    @Test func `a watch delivers every sample in order`() {
        final class Seen: @unchecked Sendable { var angles: [Double] = [] }
        let seen = Seen()
        let (hinge, _, captures) = makeHinge { _ in }
        let watch = hinge.watch { seen.angles.append($0.degrees) }
        captures.onBytes?(Data((banner
            + "• +0.000s : Angle:  3.8°  Mech:  3.8°  Velocity:+0.0°/s  AngleValid:Y  VelocityValid:N  Range:0-180°\n"
            + "• +0.030s : Angle: 16.2°  Mech: 16.2°  Velocity:+0.0°/s  AngleValid:Y  VelocityValid:N  Range:0-180°\n").utf8))
        captures.onBytes?(Data("• +0.080s : Angle: 88.2°  Mech: 88.2°  Velocity:+0.0°/s  AngleValid:Y  VelocityValid:N  Range:0-180°\n".utf8))
        #expect(seen.angles == [3.8, 16.2, 88.2])
        watch.cancel()
    }

    /// The monitor is asked for every change, not the default 1° / 1 s
    /// cadence, and for as long as a session could plausibly last.
    @Test func `a watch asks devicectl for every change for a long time`() {
        let (hinge, _, captures) = makeHinge { _ in }
        let watch = hinge.watch { _ in }
        let args = captures.arguments ?? []
        #expect(args.prefix(4) == ["devicectl", "device", "motion", "hinge-angle"])
        #expect(args.contains("--change-threshold"))
        #expect(args.contains("--update-interval"))
        if let i = args.firstIndex(of: "--timeout"), i + 1 < args.count {
            #expect(Int(args[i + 1]) ?? 0 >= 3600)
        } else {
            Issue.record("no --timeout")
        }
        watch.cancel()
    }

    @Test func `cancelling a watch terminates the monitor`() {
        let (hinge, sub, _) = makeHinge { _ in }
        let watch = hinge.watch { _ in }
        watch.cancel()
        verify(sub).terminate().called(1)
    }

    /// Nothing after cancel: a sample the pipe still had buffered must
    /// not reach a caller that has moved on.
    @Test func `a cancelled watch drops late samples`() {
        final class Seen: @unchecked Sendable { var count = 0 }
        let seen = Seen()
        let (hinge, _, captures) = makeHinge { _ in }
        let watch = hinge.watch { _ in seen.count += 1 }
        watch.cancel()
        captures.onBytes?(Data(sample.utf8))
        #expect(seen.count == 0)
    }

    @Test func `a watch on a device without a hinge delivers nothing`() {
        final class Seen: @unchecked Sendable { var count = 0 }
        let seen = Seen()
        let (hinge, _, captures) = makeHinge { _ in }
        let watch = hinge.watch { _ in seen.count += 1 }
        captures.onBytes?(Data("Error: Hinge angle monitoring is not available on this device.\n".utf8))
        captures.onExit?(1)
        #expect(seen.count == 0)
        watch.cancel()
    }
}
