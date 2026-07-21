import Testing
import Foundation
@testable import BaguetteCore

/// A staged camera source lands in a directory named after the
/// simulator it belongs to, and that udid arrives straight off the
/// request path — so the slot name is the boundary that keeps a crafted
/// udid from naming somewhere else on the filesystem.
@Suite("CameraSourceSlot")
struct CameraSourceSlotTests {

    @Test func `a real udid names its own slot`() {
        let slot = CameraSourceSlot(udid: "A1B2C3D4-5E6F-7089-ABCD-EF0123456789")
        #expect(slot?.name == "A1B2C3D4-5E6F-7089-ABCD-EF0123456789")
    }

    @Test func `distinct udids never share a slot`() {
        #expect(CameraSourceSlot(udid: "sim-A") != CameraSourceSlot(udid: "sim-B"))
    }

    @Test func `a udid carrying a path separator has no slot`() {
        #expect(CameraSourceSlot(udid: "../../etc") == nil)
        #expect(CameraSourceSlot(udid: "a/b") == nil)
        #expect(CameraSourceSlot(udid: "..") == nil)
    }

    /// `udidParam` percent-decodes, so `%2F` reaches us as a real slash
    /// and `.` / `..` as real dots — the traversal payloads have to die
    /// here rather than at the URL layer.
    @Test func `a udid that decodes into a traversal has no slot`() {
        #expect(CameraSourceSlot(udid: "..%2F..%2Ftmp".removingPercentEncoding!) == nil)
    }

    @Test func `an empty udid has no slot`() {
        #expect(CameraSourceSlot(udid: "") == nil)
    }

    @Test func `a udid with a null byte or whitespace has no slot`() {
        #expect(CameraSourceSlot(udid: "sim\0evil") == nil)
        #expect(CameraSourceSlot(udid: "sim evil") == nil)
    }

    @Test func `an absurdly long udid has no slot`() {
        #expect(CameraSourceSlot(udid: String(repeating: "A", count: 300)) == nil)
    }
}
