import Testing
import Foundation
@testable import BaguetteCore

/// Domain coverage for `MotionShake` — the value that owns the UIKit
/// shake notification name and the `simctl spawn notifyutil` argv that
/// posts it into a booted simulator's guest notify namespace.
@Suite("MotionShake")
struct MotionShakeTests {

    @Test func `posts the UIKit shake notification via simctl spawn notifyutil into the guest namespace`() {
        let shake = MotionShake()
        #expect(shake.simctlArguments(udid: "ABC-123") == [
            "simctl", "spawn", "ABC-123", "notifyutil", "-p",
            "com.apple.UIKit.SimulatorShake",
        ])
    }

    @Test func `carries the private UIKit Darwin notification name`() {
        #expect(MotionShake.notificationName == "com.apple.UIKit.SimulatorShake")
    }
}
