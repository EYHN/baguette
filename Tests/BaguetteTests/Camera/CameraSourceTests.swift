import Testing
import Foundation
@testable import BaguetteCore

@Suite("CameraSource")
struct CameraSourceTests {

    @Test func `a webcam source reports the webcam wire kind`() {
        #expect(CameraSource.device(uid: "U-1").wireKind == "webcam")
    }

    @Test func `an image-file source reports the image wire kind`() {
        #expect(CameraSource.image(path: "/tmp/pic.png").wireKind == "image")
    }

    @Test func `a video-file source reports the video wire kind`() {
        #expect(CameraSource.video(path: "/tmp/clip.mp4").wireKind == "video")
    }

    @Test func `sources are equal by kind and payload`() {
        #expect(CameraSource.device(uid: "U") == CameraSource.device(uid: "U"))
        #expect(CameraSource.device(uid: "U") != CameraSource.device(uid: "V"))
        #expect(CameraSource.image(path: "/a") != CameraSource.video(path: "/a"))
    }
}
