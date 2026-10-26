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
        var keys: [(HIDUsage, [HIDUsage], TimeInterval)] = []
    }

    private func make(refusing: Bool = false, failure: HingeError = .toolMissing) -> (FoldableInput, MockInput, Presses) {
        let touches = MockInput()
        let keys = MockDeviceKeys()
        let presses = Presses()
        given(keys).press(.any, holding: .any, hold: .any).willProduce { usage, modifiers, hold in
            if refusing { throw failure }
            presses.keys.append((usage, modifiers, hold))
        }
        return (FoldableInput(touches: touches, keys: keys), touches, presses)
    }

    @Test func `should press a foldable's hardware keys as Device Hub presses them`() {
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
        #expect(presses.keys.map(\.2) == [0.25, 0.25, 0.25, 0.25, 2])
    }

    @Test func `should send touches and keyless buttons to the panel on a foldable`() {
        let (input, touches, presses) = make()
        given(touches).tap(at: .any, size: .any, duration: .any, edge: .any).willReturn(true)
        given(touches).button(.any, duration: .any).willReturn(true)
        #expect(input.tap(at: Point(x: 1, y: 2), size: Size(width: 10, height: 20), duration: 0.05, edge: nil))
        #expect(input.button(.home, duration: 0) == true)
        #expect(presses.keys.isEmpty)
        verify(touches).button(.value(.home), duration: .value(0)).called(1)
    }

    @Test func `a keystroke the guest has no tool for falls back to the host's own keyboard`() {
        let (input, touches, _) = make(refusing: true)
        given(touches).key(.any, modifiers: .any, duration: .any).willReturn(true)
        let a = KeyboardKey.from(wireCode: "KeyA")!
        #expect(input.key(a, modifiers: [.shift], duration: 0) == true)
        verify(touches).key(.value(a), modifiers: .value([.shift]), duration: .value(0)).called(1)
    }

    @Test func `a key the guest has no tool for falls back to the host's own press`() {
        // A build without `HingeControl` — a host embedding the library
        // without its resource bundle — still has the legacy button path.
        let (input, touches, _) = make(refusing: true)
        given(touches).button(.any, duration: .any).willReturn(true)
        #expect(input.button(.volumeUp, duration: 0) == true)
        verify(touches).button(.value(.volumeUp), duration: .value(0)).called(1)
    }

    @Test func `should type a key on a foldable through the guest with its modifiers held`() {
        let (input, touches, presses) = make()
        let a = KeyboardKey.from(wireCode: "KeyA")!
        #expect(input.key(a, modifiers: [.command, .shift], duration: 0))
        #expect(input.key(a, modifiers: [], duration: 0.5))
        #expect(presses.keys.map(\.0) == [HIDUsage(page: 7, usage: 4), HIDUsage(page: 7, usage: 4)])
        // Held in a fixed order, so a chord always presses the same way.
        #expect(presses.keys.map(\.1) == [
            [HIDUsage(page: 7, usage: 0xE3), HIDUsage(page: 7, usage: 0xE1)], [],
        ])
        // A keystroke's default hold is the panel's 100 ms tap.
        #expect(presses.keys.map(\.2) == [0.1, 0.5])
        verify(touches).key(.any, modifiers: .any, duration: .any).called(0)
    }

    @Test func `should fail a keystroke when the guest refuses the key`() {
        let (input, _, _) = make(refusing: true, failure: .toolFailed(status: 1))
        #expect(input.key(KeyboardKey.from(wireCode: "KeyA")!, modifiers: [], duration: 0) == false)
    }
}
