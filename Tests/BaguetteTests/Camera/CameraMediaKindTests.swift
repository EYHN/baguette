import Testing
import Foundation
@testable import BaguetteCore

@Suite("CameraMediaKind")
struct CameraMediaKindTests {

    @Test func `classifies still-image extensions as image`() {
        for ext in ["png", "jpg", "jpeg", "gif", "heic", "heif"] {
            #expect(CameraMediaKind.at(URL(fileURLWithPath: "/tmp/pic.\(ext)")) == .image)
        }
    }

    @Test func `classifies movie-container extensions as video`() {
        for ext in ["mov", "mp4", "m4v"] {
            #expect(CameraMediaKind.at(URL(fileURLWithPath: "/tmp/clip.\(ext)")) == .video)
        }
    }

    @Test func `classification is case-insensitive`() {
        #expect(CameraMediaKind.at(URL(fileURLWithPath: "/tmp/PIC.PNG")) == .image)
        #expect(CameraMediaKind.at(URL(fileURLWithPath: "/tmp/CLIP.MP4")) == .video)
    }

    @Test func `rejects extensions the camera can't source from`() {
        #expect(CameraMediaKind.at(URL(fileURLWithPath: "/tmp/doc.pdf")) == nil)
        #expect(CameraMediaKind.at(URL(fileURLWithPath: "/tmp/app.ipa")) == nil)
        #expect(CameraMediaKind.at(URL(fileURLWithPath: "/tmp/noext")) == nil)
    }
}
