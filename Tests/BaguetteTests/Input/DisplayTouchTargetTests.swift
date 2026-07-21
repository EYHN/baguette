import Testing
@testable import BaguetteCore

/// Phone input keeps the integrated digitizer constant. CarPlay input
/// derives its HID target from the live connected screen id — never
/// from creatable plist 101 / hard-coded 0x40000065.
@Suite("DisplayTouchTarget")
struct DisplayTouchTargetTests {

    @Test func `phone always uses the integrated digitizer constant`() {
        let target = DisplayTouchTarget.resolve(
            kind: .phone,
            connectedScreenId: 1,
            derive: { _ in 0xDEAD_BEEF }
        )
        #expect(target == IndigoHIDTouchTarget.phone)
    }

    @Test func `carPlay uses the derived target for the live connected screen id`() {
        var seen: UInt32?
        let target = DisplayTouchTarget.resolve(
            kind: .carPlay,
            connectedScreenId: 204,
            derive: { id in
                seen = id
                return id | 0x4000_0000
            }
        )
        #expect(seen == 204)
        #expect(target == 0x4000_00CC)
        #expect(target != IndigoHIDTouchTarget.phone)
        #expect(target != 0x4000_0065)
    }

    @Test func `carPlay falls back to phone digitizer when derivation fails`() {
        let target = DisplayTouchTarget.resolve(
            kind: .carPlay,
            connectedScreenId: 2,
            derive: { _ in nil }
        )
        #expect(target == IndigoHIDTouchTarget.phone)
    }
}
