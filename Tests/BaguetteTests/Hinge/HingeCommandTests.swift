import Testing
import Foundation
@testable import Baguette

/// `POST /simulators/<udid>/hinge` and `baguette hinge`: a pose by name —
/// Device Hub's three — or an angle, swept over a duration.
@Suite("HingeCommand")
struct HingeCommandTests {
    @Test func `a pose by name is Device Hub's angle for it`() throws {
        #expect(try HingeCommand.parse(pose: "closed", angle: nil, duration: nil).degrees == 0)
        #expect(try HingeCommand.parse(pose: "open", angle: nil, duration: nil).degrees == 130)
        #expect(try HingeCommand.parse(pose: "flat", angle: nil, duration: nil).degrees == 180)
    }

    @Test func `an angle is taken as given, within the hinge's range`() throws {
        let command = try HingeCommand.parse(pose: nil, angle: "95.5", duration: "1.2")
        #expect(command == HingeCommand(degrees: 95.5, duration: 1.2))
        #expect(throws: HingeCommandError.angleOutOfRange) {
            try HingeCommand.parse(pose: nil, angle: "181", duration: nil)
        }
    }

    @Test func `the sweep takes Device Hub's time unless told otherwise, and never a negative one`() throws {
        #expect(try HingeCommand.parse(pose: "open", angle: nil, duration: nil).duration == HingeCommand.defaultDuration)
        #expect(throws: HingeCommandError.invalidDuration) {
            try HingeCommand.parse(pose: "open", angle: nil, duration: "-1")
        }
    }

    @Test func `one of pose and angle is required, and a pose must be one of the three`() {
        #expect(throws: HingeCommandError.missingTarget) {
            try HingeCommand.parse(pose: nil, angle: nil, duration: nil)
        }
        #expect(throws: HingeCommandError.unknownPose("tent")) {
            try HingeCommand.parse(pose: "tent", angle: nil, duration: nil)
        }
    }
}
