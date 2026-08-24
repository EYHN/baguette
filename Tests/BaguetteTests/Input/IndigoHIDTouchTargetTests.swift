import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// An input surface dispatches touches to an injectable Indigo HID
/// target. Phone defaults to `IndigoHIDTouchTarget.phone` (`0x32`);
/// CarPlay callers pass a live-derived target.
@Suite("IndigoHIDTouchTarget")
struct IndigoHIDTouchTargetTests {

    @Test func `IndigoHIDInput defaults touch target to phone digitizer`() {
        let host = MockDeviceHost()
        let input = IndigoHIDInput(udid: "ghost", host: host)
        #expect(input.touchTarget == IndigoHIDTouchTarget.phone)
        #expect(input.touchTarget == 0x32)
    }

    @Test func `IndigoHIDInput retains a custom touch target`() {
        let host = MockDeviceHost()
        let carPlay: UInt32 = 0x4000_0065
        let input = IndigoHIDInput(udid: "ghost", host: host, touchTarget: carPlay)
        #expect(input.touchTarget == carPlay)
    }

    @Test func `IOHIDDigitizerDispatch patch writes the given target into message slots`() {
        let size = 0x110
        guard let buf = malloc(size) else {
            Issue.record("malloc failed")
            return
        }
        defer { free(buf) }
        memset(buf, 0, size)

        let custom: UInt32 = 0x4000_0065
        IOHIDDigitizerDispatch.patch(message: buf, edge: .none, target: custom)

        #expect(buf.load(fromByteOffset: 0x6c, as: UInt32.self) == custom)
        #expect(buf.load(fromByteOffset: 0x10c, as: UInt32.self) == custom)
    }

    @Test func `IOHIDDigitizerDispatch patch defaults target to phone digitizer`() {
        let size = 0x110
        guard let buf = malloc(size) else {
            Issue.record("malloc failed")
            return
        }
        defer { free(buf) }
        memset(buf, 0, size)

        IOHIDDigitizerDispatch.patch(message: buf, edge: .none)

        #expect(buf.load(fromByteOffset: 0x6c, as: UInt32.self) == IndigoHIDTouchTarget.phone)
        #expect(buf.load(fromByteOffset: 0x10c, as: UInt32.self) == 0x32)
    }
}
