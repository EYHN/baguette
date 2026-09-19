import Testing
import Foundation
import Mockable
@testable import Baguette

/// On iPhone Duo the legacy button path lands on a touchscreen service
/// and SpringBoard ignores it; the keys Device Hub presses ride the guest
/// daemon's own buttons service. A foldable's input presses those keys
/// the way Device Hub does and leaves everything else to the panel.
@Suite("FoldableInput")
struct FoldableInputTests {

    final class Presses: @unchecked Sendable {
        var keys: [(HIDUsage, TimeInterval)] = []
    }

    private func make(refusing: Bool = false) -> (FoldableInput, MockInput, Presses) {
        let touches = MockInput()
        let keys = MockDeviceKeys()
        let presses = Presses()
        given(keys).press(.any, hold: .any).willProduce { usage, hold in
            if refusing { throw HingeError.toolMissing }
            presses.keys.append((usage, hold))
        }
        return (FoldableInput(touches: touches, keys: keys), touches, presses)
    }

    @Test func `hardware keys are pressed as Device Hub presses them`() {
        let (input, _, presses) = make()
        #expect(input.button(.volumeUp, duration: 0) == true)
        #expect(input.button(.volumeDown, duration: 0) == true)
        #expect(input.button(.power, duration: 0) == true)
        #expect(input.button(.lock, duration: 0) == true)
        #expect(input.button(.action, duration: 2) == true)
        #expect(presses.keys.map(\.0) == [
            HIDUsage(page: 12, usage: 233), HIDUsage(page: 12, usage: 234),
            HIDUsage(page: 12, usage: 48), HIDUsage(page: 12, usage: 48),
            HIDUsage(page: 0xFF00, usage: 0x66),
        ])
        // Device Hub holds a key a quarter second; a longer hold is the caller's.
        #expect(presses.keys.map(\.1) == [0.25, 0.25, 0.25, 0.25, 2])
    }

    @Test func `touches and buttons the guest has no key for go to the panel`() {
        let (input, touches, presses) = make()
        given(touches).tap(at: .any, size: .any, duration: .any, edge: .any).willReturn(true)
        given(touches).button(.any, duration: .any).willReturn(true)
        #expect(input.tap(at: Point(x: 1, y: 2), size: Size(width: 10, height: 20), duration: 0.05, edge: nil))
        #expect(input.button(.home, duration: 0) == true)
        #expect(presses.keys.isEmpty)
        verify(touches).button(.value(.home), duration: .value(0)).called(1)
    }

    @Test func `a key the guest refuses is a failed press`() {
        let (input, _, _) = make(refusing: true)
        #expect(input.button(.volumeUp, duration: 0) == false)
    }
}
