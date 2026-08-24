import Testing
@testable import BaguetteCore

/// CarPlay's compositor often goes idle on a static home screen, so
/// callback-only capture starves the browser. An idle floor keeps
/// emitting frames while the surface is live.
@Suite("ScreenIdleFloor")
struct ScreenIdleFloorTests {
    @Test func carPlayEnablesAnIdleFloor() {
        #expect(ScreenIdleFloor.isEnabled(for: .carPlay))
    }

    @Test func phoneAlsoEnablesAnIdleFloor() {
        // Phone maps/animations usually callback, but a quiet lock
        // screen still needs a floor — same policy as the spike.
        #expect(ScreenIdleFloor.isEnabled(for: .phone))
    }

    @Test func intervalIsFiveFramesPerSecond() {
        #expect(ScreenIdleFloor.intervalNanoseconds == 200_000_000)
    }
}
