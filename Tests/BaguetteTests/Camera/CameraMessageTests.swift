import Testing
import Foundation
@testable import BaguetteCore

@Suite("CameraMessage parsing")
struct CameraMessageTests {

    @Test func `parses camera_list`() throws {
        let msg = try CameraMessage.parse(["type": "camera_list"])
        #expect(msg == .list)
    }

    @Test func `parses camera_start with a webcam device + flags`() throws {
        let msg = try CameraMessage.parse([
            "type": "camera_start",
            "deviceUID": "U-1",
            "fit": "fill",
            "mirror": true,
        ])
        #expect(msg == .start(
            source: .webcam(deviceUID: "U-1"),
            flags: CameraFlags(fillGravity: true, mirror: true)
        ))
    }

    @Test func `an explicit webcam source parses like the default`() throws {
        let msg = try CameraMessage.parse([
            "type": "camera_start", "source": "webcam", "deviceUID": "U-1",
        ])
        #expect(msg == .start(source: .webcam(deviceUID: "U-1"), flags: CameraFlags()))
    }

    @Test func `an image source needs no deviceUID`() throws {
        let msg = try CameraMessage.parse([
            "type": "camera_start", "source": "image", "fit": "fill",
        ])
        #expect(msg == .start(
            source: .image,
            flags: CameraFlags(fillGravity: true, mirror: false)
        ))
    }

    @Test func `a video source needs no deviceUID`() throws {
        let msg = try CameraMessage.parse([
            "type": "camera_start", "source": "video",
        ])
        #expect(msg == .start(source: .video, flags: CameraFlags()))
    }

    @Test func `an unknown source kind fails parse`() {
        #expect(throws: (any Error).self) {
            try CameraMessage.parse(["type": "camera_start", "source": "hologram"])
        }
    }

    @Test func `camera_start defaults missing flags to fit + no mirror`() throws {
        let msg = try CameraMessage.parse([
            "type": "camera_start", "deviceUID": "U",
        ])
        #expect(msg == .start(source: .webcam(deviceUID: "U"), flags: CameraFlags()))
    }

    @Test func `parses camera_stop`() throws {
        let msg = try CameraMessage.parse(["type": "camera_stop"])
        #expect(msg == .stop)
    }

    @Test func `parses camera_set_flags`() throws {
        let msg = try CameraMessage.parse([
            "type": "camera_set_flags",
            "fit": "fit",
            "mirror": true,
        ])
        #expect(msg == .setFlags(CameraFlags(fillGravity: false, mirror: true)))
    }

    @Test func `unknown type fails parse`() {
        #expect(throws: (any Error).self) {
            try CameraMessage.parse(["type": "camera_wibble"])
        }
    }

    @Test func `missing deviceUID on a webcam camera_start fails parse`() {
        #expect(throws: (any Error).self) {
            try CameraMessage.parse(["type": "camera_start"])
        }
    }
}
