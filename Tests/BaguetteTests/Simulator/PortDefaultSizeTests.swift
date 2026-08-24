import Foundation
import Testing
@testable import BaguetteCore

/// Framebuffer port default size is read only from accessors the port
/// actually exposes — missing KVC keys must return nil, not trap.
@Suite("PortDefaultSize")
struct PortDefaultSizeTests {
    @Test func returnsNilWhenPortExposesNoSizeAccessors() {
        #expect(PortDefaultSize.read(from: NSObject()) == nil)
    }

    @Test func readsDefaultWidthAndHeightWhenPresent() {
        final class FakePort: NSObject {
            @objc var defaultWidth: NSNumber = 800
            @objc var defaultHeight: NSNumber = 480
        }
        #expect(PortDefaultSize.read(from: FakePort()) == Size(width: 800, height: 480))
    }

    @Test func fallsBackToWidthAndHeightKeys() {
        final class FakePort: NSObject {
            @objc var width: NSNumber = 390
            @objc var height: NSNumber = 844
        }
        #expect(PortDefaultSize.read(from: FakePort()) == Size(width: 390, height: 844))
    }
}
