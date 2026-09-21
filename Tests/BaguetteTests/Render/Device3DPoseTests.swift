import Foundation
import Testing
@testable import BaguetteCore

// Device Hub's pose picker, on the page: shut, open or flat, driven on the
// device's own hinge. The envelope rides the 3D socket beside
// `set_3d_camera`.
@Suite("Device3DPose")
struct Device3DPoseTests {
    @Test func `parses a pose to fold to`() throws {
        let pose = try #require(try Device3DPose.parsing(json: Data(#"{"type":"set_pose","hingeDegrees":130}"#.utf8)))
        #expect(pose == .fold(hingeDegrees: 130, duration: nil))
    }

    @Test func `a pose may say how long its sweep takes; the hinge slider asks for none`() throws {
        let picked = try #require(try Device3DPose.parsing(json: Data(#"{"type":"set_pose","hingeDegrees":130}"#.utf8)))
        #expect(picked == .fold(hingeDegrees: 130, duration: nil))
        let dragged = try #require(try Device3DPose.parsing(json: Data(#"{"type":"set_pose","hingeDegrees":72.5,"duration":0}"#.utf8)))
        #expect(dragged == .fold(hingeDegrees: 72.5, duration: 0))
        #expect(throws: DeviceModelError.invalidRenderOptions) {
            _ = try Device3DPose.parsing(json: Data(#"{"type":"set_pose","hingeDegrees":90,"duration":-1}"#.utf8))
        }
    }

    @Test func `ignores other envelopes and rejects angles off the hinge`() throws {
        #expect(try Device3DPose.parsing(json: Data(#"{"type":"set_fps","fps":30}"#.utf8)) == nil)
        #expect(throws: DeviceModelError.invalidRenderOptions) {
            _ = try Device3DPose.parsing(json: Data(#"{"type":"set_pose","hingeDegrees":200}"#.utf8))
        }
        #expect(throws: DeviceModelError.invalidRenderOptions) {
            _ = try Device3DPose.parsing(json: Data(#"{"type":"set_pose"}"#.utf8))
        }
    }
}
