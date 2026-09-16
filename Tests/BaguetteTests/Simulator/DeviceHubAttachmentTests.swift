import Testing
@testable import Baguette

/// Xcode 27's Device Hub attaches a guest HID daemon (`dtuhidd`) to every
/// booted simulator. It announces itself through one Darwin notify state
/// in the guest, and that state is the whole signal baguette reads to
/// decide whether the legacy Indigo input surface has been shadowed.
@Suite("DeviceHubAttachment")
struct DeviceHubAttachmentTests {

    @Test func `reads the notify state Device Hub's HID daemon publishes`() {
        #expect(DeviceHubAttachment.stateKey == "com.apple.coredevice.dtuhidd.active")
    }

    @Test func `an active state means Device Hub has attached`() {
        let attachment = DeviceHubAttachment.parsing("com.apple.coredevice.dtuhidd.active 1\n")
        #expect(attachment.attached)
    }

    @Test func `a zero state means the surface is unshadowed`() {
        let attachment = DeviceHubAttachment.parsing("com.apple.coredevice.dtuhidd.active 0\n")
        #expect(!attachment.attached)
    }

    @Test func `a device without the state has never seen Device Hub`() {
        // Xcode 26 runtimes never publish the key; `notifyutil -g` on a
        // key nothing set prints 0, and a failed spawn prints nothing.
        #expect(!DeviceHubAttachment.parsing(nil).attached)
        #expect(!DeviceHubAttachment.parsing("").attached)
        #expect(!DeviceHubAttachment.parsing("garbage").attached)
    }

    @Test func `only the named key counts`() {
        #expect(!DeviceHubAttachment.parsing("com.apple.something.else 1\n").attached)
    }

    @Test func `an attached surface advises the heal command`() {
        let advisory = DeviceHubAttachment(attached: true).advisory(udid: "ABC")
        #expect(advisory?.contains("baguette heal --udid ABC") == true)
        #expect(advisory?.contains("Device Hub") == true)
    }

    @Test func `an unshadowed surface has nothing to advise`() {
        #expect(DeviceHubAttachment(attached: false).advisory(udid: "ABC") == nil)
    }
}
