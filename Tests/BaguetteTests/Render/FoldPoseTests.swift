import Foundation
import Testing
@testable import Baguette

// The hinge angle poses the book. The shutting clip runs from flat (its
// start) to shut (the definition's shut time); it raises the left half
// alone, so the whole device turns back by half the fold to centre the
// bend — fully above the open pose, as Device Hub draws it, handing over
// to the cover-forward pose as the book shuts.
@Suite("FoldPose")
struct FoldPoseTests {
    let fold = DeviceModelFold(
        clip: "l_over_r", shutTime: 5.0,
        coverMaterial: "cover", coverTextureSize: RenderDimensions(width: 1, height: 1),
        openPoseDegrees: 130
    )

    @Test func `flat is the clip's start with no turn`() {
        let pose = FoldPose.at(degrees: 180, fold: fold)
        #expect(pose.clipTime == 0)
        #expect(pose.yawDegrees == 0)
    }

    @Test func `shut is the clip's shut time, the cover facing the camera`() {
        let pose = FoldPose.at(degrees: 0, fold: fold)
        #expect(pose.clipTime == 5.0)
        #expect(pose.yawDegrees == 0)
    }

    @Test func `the open pose is centred: half the fold turned back`() {
        let pose = FoldPose.at(degrees: 130, fold: fold)
        #expect(abs(pose.clipTime - 50.0 / 180 * 5) < 1e-9)
        #expect(pose.yawDegrees == -25)
    }

    @Test func `between open and shut the turn hands over in proportion`() {
        let pose = FoldPose.at(degrees: 65, fold: fold)
        // fold 115°, half 57.5°, share 0.5
        #expect(abs(pose.yawDegrees - (-28.75)) < 1e-9)
    }

    @Test func `angles outside the hinge's range are clamped`() {
        #expect(FoldPose.at(degrees: 200, fold: fold).clipTime == 0)
        #expect(FoldPose.at(degrees: -5, fold: fold).clipTime == 5.0)
    }
}

// The book stands the way the guest is held. The lit panel has an
// orientation of its own — the unfolded panel is landscape-left lying
// flat in the model, the cover portrait — and each step of the
// interface cycle turns the device another quarter turn.
@Suite("InterfaceRoll")
struct InterfaceRollTests {
    @Test func `the lit panel's own orientation is the model as it stands`() {
        #expect(InterfaceRoll.degrees(.landscapeLeft, litPanel: .secondary) == 0)
        #expect(InterfaceRoll.degrees(.portrait, litPanel: .primary) == 0)
    }

    @Test func `a portrait interface on the unfolded panel stands the book up`() {
        #expect(InterfaceRoll.degrees(.portrait, litPanel: .secondary) == -90)
        #expect(InterfaceRoll.degrees(.portraitUpsideDown, litPanel: .secondary) == 90)
        #expect(InterfaceRoll.degrees(.landscapeRight, litPanel: .secondary) == 180)
    }

    @Test func `the shut cover turns the same way`() {
        #expect(InterfaceRoll.degrees(.landscapeLeft, litPanel: .primary) == 90)
        #expect(InterfaceRoll.degrees(.landscapeRight, litPanel: .primary) == -90)
    }
}
