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

    // MARK: - foldable

    /// iPhone Duo (iOS 27.1): the cover (`primary`, 1398×2034) and the
    /// unfolded panel (`primary-1`, 2007×2853). Both are portrait and
    /// both are Integrated, so shape cannot pick; the hinge says which
    /// one the guest lights, and the phone plane binds that one.
    private let coverPanel = FramebufferPortSnapshot(
        portName: "com.apple.framebuffer.display",
        connectedScreenId: 1,
        size: Size(width: 1398, height: 2034),
        panel: .primary
    )
    private let unfoldedPanel = FramebufferPortSnapshot(
        portName: "com.apple.framebuffer.display",
        connectedScreenId: 3,
        size: Size(width: 2007, height: 2853),
        panel: .secondary,
        orientation: .landscapeLeft
    )

    @Test func `folded, phone binds the cover panel, not the larger dark one`() throws {
        let binding = try ConnectedScreens.binding(
            kind: .phone,
            ports: [unfoldedPanel, coverPanel],
            litPanel: .primary
        )
        #expect(binding.connectedScreenId == 1)
        #expect(binding.size == coverPanel.size)
    }

    @Test func `unfolded, phone binds the unfolded panel`() throws {
        let binding = try ConnectedScreens.binding(
            kind: .phone,
            ports: [unfoldedPanel, coverPanel],
            litPanel: .secondary
        )
        #expect(binding.connectedScreenId == 3)
        #expect(binding.size == unfoldedPanel.size)
        // The guest turned the unfolded panel; the binding says so.
        #expect(binding.orientation == .landscapeLeft)
    }

    /// With no hinge reading the device is taken as it boots: folded.
    @Test func `without a hinge reading the cover is the phone`() throws {
        let binding = try ConnectedScreens.binding(
            kind: .phone,
            ports: [unfoldedPanel, coverPanel]
        )
        #expect(binding.connectedScreenId == 1)
    }

    /// A single-panel device has only a primary; asking for the
    /// secondary must not bind nothing.
    @Test func `a device with one panel binds it whatever the hinge says`() throws {
        let binding = try ConnectedScreens.binding(
            kind: .phone,
            ports: [coverPanel, carPlayPort],
            litPanel: .secondary
        )
        #expect(binding.connectedScreenId == 1)
    }

    /// The second panel is portrait, so it is never mistaken for an
    /// external either.
    @Test func `a foldable's second panel does not bind as CarPlay`() {
        #expect(throws: FramebufferSelectionError.noMatchingPort(.carPlay)) {
            try ConnectedScreens.binding(
                kind: .carPlay,
                ports: [unfoldedPanel, coverPanel]
            )
        }
    }

    /// Without a named panel — every device before the Duo, and older
    /// enumerate output — shape still decides, exactly as before.
    @Test func `without a named panel the largest portrait port is still the phone`() throws {
        let binding = try ConnectedScreens.binding(
            kind: .phone,
            ports: [overlayPort, phonePort, carPlayPort]
        )
        #expect(binding.connectedScreenId == 1)
    }

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

    /// A 4K external out-measures every phone, so "the device is the
    /// largest plane" quietly hands the device slot to the external —
    /// and the portrait phone left over is not a landscape external, so
    /// the pane then reported nothing attached for a screen the user was
    /// looking at. The device is picked by its own shape, not by size.
    @Test func `carPlay binds a 4K external larger than the phone plane`() throws {
        let uhd = FramebufferPortSnapshot(
            portName: "com.apple.framebuffer.display",
            connectedScreenId: 2,
            size: Size(width: 3840, height: 2160)
        )
        let binding = try ConnectedScreens.binding(
            kind: .carPlay,
            ports: [phonePort, uhd]
        )
        #expect(binding.connectedScreenId == 2)
        #expect(binding.size == uhd.size)
    }

    /// Same list, other plane: the phone must not be handed the external
    /// either, or the device pane streams the car's screen.
    @Test func `phone keeps its own plane when a larger external is attached`() throws {
        let uhd = FramebufferPortSnapshot(
            portName: "com.apple.framebuffer.display",
            connectedScreenId: 2,
            size: Size(width: 3840, height: 2160)
        )
        let binding = try ConnectedScreens.binding(
            kind: .phone,
            ports: [uhd, phonePort]
        )
        #expect(binding.connectedScreenId == 1)
        #expect(binding.size == phonePort.size)
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

/// The bound panel's size in points — what accessibility frames are
/// expressed in. On a foldable the lit panel changes with the hinge,
/// so the AX space has to come from the binding, not from the device
/// type's single `mainScreenSize`.
@Suite("DisplayBinding point size")
struct DisplayBindingPointSizeTests {

    @Test func `is the pixel size over the scale`() {
        let unfolded = DisplayBinding(
            kind: .phone, connectedScreenId: 3,
            portName: "com.apple.framebuffer.display",
            size: Size(width: 2007, height: 2853)
        )
        #expect(unfolded.pointSize(scale: 3) == Size(width: 669, height: 951))
    }

    @Test func `a zero or negative scale yields no point size`() {
        let cover = DisplayBinding(
            kind: .phone, connectedScreenId: 1,
            portName: "com.apple.framebuffer.display",
            size: Size(width: 1398, height: 2034)
        )
        #expect(cover.pointSize(scale: 0) == nil)
        #expect(cover.pointSize(scale: -1) == nil)
    }
}
