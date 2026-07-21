import Testing
@testable import BaguetteCore

/// Port selection over live framebuffer snapshots: phone is the largest
/// plane; CarPlay is the best remaining external after that winner is
/// excluded, and refuses to bind without a connected screen id.
@Suite("ConnectedScreens")
struct ConnectedScreensTests {

    private let phonePort = FramebufferPortSnapshot(
        portName: "com.apple.framebuffer.display",
        connectedScreenId: 1,
        size: Size(width: 1179, height: 2556)
    )
    private let carPlayPort = FramebufferPortSnapshot(
        portName: "com.apple.framebuffer.display",
        connectedScreenId: 204,
        size: Size(width: 800, height: 480)
    )
    private let overlayPort = FramebufferPortSnapshot(
        portName: "com.apple.framebuffer.display",
        connectedScreenId: 2,
        size: Size(width: 100, height: 100)
    )

    @Test func `phone binds the largest-area framebuffer port`() throws {
        let binding = try ConnectedScreens.binding(
            kind: .phone,
            ports: [overlayPort, phonePort, carPlayPort]
        )
        #expect(binding.kind == .phone)
        #expect(binding.connectedScreenId == 1)
        #expect(binding.portName == phonePort.portName)
        #expect(binding.size == phonePort.size)
    }

    @Test func `carPlay excludes the phone winner and binds the best external`() throws {
        let binding = try ConnectedScreens.binding(
            kind: .carPlay,
            ports: [phonePort, carPlayPort, overlayPort]
        )
        #expect(binding.kind == .carPlay)
        #expect(binding.connectedScreenId == 204)
        #expect(binding.size == carPlayPort.size)
    }

    @Test func `carPlay prefers runtime area over plist 720x480 when areas differ`() throws {
        let plistSized = FramebufferPortSnapshot(
            portName: "com.apple.framebuffer.display",
            connectedScreenId: 101,
            size: Size(width: 720, height: 480)
        )
        let runtimeLarger = FramebufferPortSnapshot(
            portName: "com.apple.framebuffer.display",
            connectedScreenId: 204,
            size: Size(width: 800, height: 480)
        )
        let binding = try ConnectedScreens.binding(
            kind: .carPlay,
            ports: [phonePort, plistSized, runtimeLarger]
        )
        #expect(binding.connectedScreenId == 204)
        #expect(binding.size == runtimeLarger.size)
    }

    @Test func `carPlay uses 720x480 proximity only as an area tie-break`() throws {
        let nearPlist = FramebufferPortSnapshot(
            portName: "com.apple.framebuffer.display",
            connectedScreenId: 101,
            size: Size(width: 720, height: 480)
        )
        let sameAreaFarther = FramebufferPortSnapshot(
            portName: "com.apple.framebuffer.display",
            connectedScreenId: 205,
            size: Size(width: 960, height: 360) // same 345600 area, farther from 720×480
        )
        let binding = try ConnectedScreens.binding(
            kind: .carPlay,
            ports: [phonePort, sameAreaFarther, nearPlist]
        )
        #expect(binding.connectedScreenId == 101)
        #expect(binding.size == nearPlist.size)
    }

    @Test func `carPlay throws when no external remains after excluding phone`() {
        #expect(throws: FramebufferSelectionError.noMatchingPort(.carPlay)) {
            try ConnectedScreens.binding(kind: .carPlay, ports: [phonePort])
        }
    }

    @Test func `carPlay refuses a second phone-sized plane disguised as external`() {
        let phoneMirror = FramebufferPortSnapshot(
            portName: "com.apple.framebuffer.display",
            connectedScreenId: 3,
            size: Size(width: 1170, height: 2532)
        )
        #expect(throws: FramebufferSelectionError.noMatchingPort(.carPlay)) {
            try ConnectedScreens.binding(
                kind: .carPlay,
                ports: [phonePort, phoneMirror]
            )
        }
    }

    @Test func `carPlay throws when the external has no connected screen id`() {
        let disconnected = FramebufferPortSnapshot(
            portName: "com.apple.framebuffer.display",
            connectedScreenId: nil,
            size: Size(width: 800, height: 480)
        )
        #expect(throws: FramebufferSelectionError.screenIdUnavailable) {
            try ConnectedScreens.binding(
                kind: .carPlay,
                ports: [phonePort, disconnected]
            )
        }
    }

    @Test func `phone throws when the port list is empty`() {
        #expect(throws: FramebufferSelectionError.noMatchingPort(.phone)) {
            try ConnectedScreens.binding(kind: .phone, ports: [])
        }
    }

    @Test func `phone throws when the winning port has no connected screen id`() {
        let headless = FramebufferPortSnapshot(
            portName: "com.apple.framebuffer.display",
            connectedScreenId: nil,
            size: Size(width: 1179, height: 2556)
        )
        #expect(throws: FramebufferSelectionError.screenIdUnavailable) {
            try ConnectedScreens.binding(kind: .phone, ports: [headless])
        }
    }
}
