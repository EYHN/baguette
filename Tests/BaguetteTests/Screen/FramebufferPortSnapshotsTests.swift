import Testing
@testable import BaguetteCore

/// Live IOSurface sizes join to Connected Screens by closest pixel size
/// so Creatable CarPlay 101 never stamps a phone or external port.
@Suite("FramebufferPortSnapshots")
struct FramebufferPortSnapshotsTests {

    @Test func `assigns connected screen ids by closest pixel size`() {
        let ports = [
            SizedFramebufferPort(
                portName: "com.apple.framebuffer.display",
                size: Size(width: 1206, height: 2622)
            ),
            SizedFramebufferPort(
                portName: "com.apple.framebuffer.display",
                size: Size(width: 800, height: 480)
            ),
        ]
        let screens = [
            ConnectedScreenRecord(
                screenId: 1,
                name: "LCD",
                screenType: .integrated,
                size: Size(width: 1206, height: 2622)
            ),
            ConnectedScreenRecord(
                screenId: 2,
                name: "TVOut",
                screenType: .tvOut,
                size: Size(width: 720, height: 480)
            ),
        ]

        let snapshots = FramebufferPortSnapshots.assigningScreenIds(
            ports: ports,
            screens: screens
        )

        #expect(snapshots.count == 2)
        #expect(snapshots[0].connectedScreenId == 1)
        #expect(snapshots[0].size == Size(width: 1206, height: 2622))
        #expect(snapshots[1].connectedScreenId == 2)
        #expect(snapshots[1].size == Size(width: 800, height: 480))
    }

    @Test func `leaves screen id nil when no connected screens remain to match`() {
        let ports = [
            SizedFramebufferPort(
                portName: "com.apple.framebuffer.display",
                size: Size(width: 100, height: 100)
            ),
        ]
        let snapshots = FramebufferPortSnapshots.assigningScreenIds(
            ports: ports,
            screens: []
        )
        #expect(snapshots[0].connectedScreenId == nil)
    }

    @Test func `phone and carPlay bindings share the assigned live screen ids`() throws {
        let ports = FramebufferPortSnapshots.assigningScreenIds(
            ports: [
                SizedFramebufferPort(
                    portName: "com.apple.framebuffer.display",
                    size: Size(width: 1179, height: 2556)
                ),
                SizedFramebufferPort(
                    portName: "com.apple.framebuffer.display",
                    size: Size(width: 800, height: 480)
                ),
            ],
            screens: [
                ConnectedScreenRecord(
                    screenId: 1,
                    name: "LCD",
                    screenType: .integrated,
                    size: Size(width: 1179, height: 2556)
                ),
                ConnectedScreenRecord(
                    screenId: 204,
                    name: "TVOut",
                    screenType: .tvOut,
                    size: Size(width: 720, height: 480)
                ),
            ]
        )

        let phone = try ConnectedScreens.binding(kind: .phone, ports: ports)
        let carPlay = try ConnectedScreens.binding(kind: .carPlay, ports: ports)

        #expect(phone.connectedScreenId == 1)
        #expect(carPlay.connectedScreenId == 204)
        #expect(carPlay.connectedScreenId != 101)
    }
}
