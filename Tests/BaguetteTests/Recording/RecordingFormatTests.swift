import Testing
import Foundation
@testable import BaguetteCore

/// The container a recording is written into is decided by the file the
/// user names — `demo.mp4` is an MP4, `demo.mov` a QuickTime movie.
@Suite("RecordingFormat")
struct RecordingFormatTests {

    @Test func `an mp4 filename records into an MP4 container`() throws {
        let format = try RecordingFormat.forFile(URL(fileURLWithPath: "/tmp/demo.mp4"))
        #expect(format == .mp4)
    }

    @Test func `a mov filename records into a QuickTime container`() throws {
        let format = try RecordingFormat.forFile(URL(fileURLWithPath: "/tmp/demo.MOV"))
        #expect(format == .mov)
    }

    @Test func `an unknown extension is rejected rather than guessed at`() {
        #expect(throws: RecordingError.unsupportedContainer("webm")) {
            _ = try RecordingFormat.forFile(URL(fileURLWithPath: "/tmp/demo.webm"))
        }
    }

    @Test func `a filename with no extension is rejected`() {
        #expect(throws: RecordingError.unsupportedContainer("")) {
            _ = try RecordingFormat.forFile(URL(fileURLWithPath: "/tmp/demo"))
        }
    }

    @Test func `the rejection message names every container baguette can write`() {
        #expect(RecordingError.unsupportedContainer("webm").message
            == "Unknown recording container 'webm'. Expected one of: mp4 | mov")
    }

    @Test func `every container advertises the list users can pick from`() {
        #expect(RecordingFormat.containerList == "mp4 | mov")
    }
}
