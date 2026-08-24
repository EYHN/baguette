import Testing
import Foundation
@testable import BaguetteCore

/// The simulator delivers a frame whenever the screen changes, which is
/// up to 60 times a second. A recording asked for 30 fps keeps every
/// other one — the cadence is what decides.
@Suite("FrameCadence")
struct FrameCadenceTests {

    /// `accepts` is mutating, so `#expect` can't call it in place —
    /// run the arrivals through and report which ones were kept.
    private func kept(fps: Int, arrivals: [Double]) -> [Double] {
        var cadence = FrameCadence(fps: fps)
        return arrivals.filter { cadence.accepts($0) }
    }

    @Test func `the first frame of a recording is always kept`() {
        #expect(kept(fps: 30, arrivals: [7.5]) == [7.5])
    }

    @Test func `frames arriving faster than the requested rate are dropped`() {
        #expect(kept(fps: 10, arrivals: [0, 0.02, 0.04, 0.1, 0.11, 0.2]) == [0, 0.1, 0.2])
    }

    @Test func `a late frame shifts the cadence instead of catching up`() {
        // The slot after 0.37 opens 0.1 s later, not on an absolute grid.
        #expect(kept(fps: 10, arrivals: [0, 0.37, 0.42, 0.48]) == [0, 0.37, 0.48])
    }

    @Test func `a frame a hair early still counts because float time never lands exactly`() {
        let interval = 1.0 / 60.0
        #expect(kept(fps: 60, arrivals: [0, interval - 0.0005]) == [0, interval - 0.0005])
    }

    @Test func `a nonsensical frame rate never divides by zero`() {
        #expect(FrameCadence(fps: 0).interval == 0)
        #expect(kept(fps: 0, arrivals: [0, 0.001, 0.002]) == [0, 0.001, 0.002])
    }

    @Test func `the interval is the reciprocal of the requested rate`() {
        #expect(FrameCadence(fps: 30).interval == 1.0 / 30.0)
    }
}
