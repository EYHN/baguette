import Testing
@testable import BaguetteCore

/// `simctl io enumerate` Connected Screens is the live topology:
/// creatable CarPlay (101) is ignored until a TVOut/CarPlay screen
/// appears under Connected Screens.
@Suite("SimctlIOEnumerate")
struct SimctlIOEnumerateTests {

    private let connectedSample = """
        Creatable Screen Properties:
        (101) CarPlay:
            Screen ID: 101
            Name: CarPlay
            Screen Type: CarPlay
            Pixel Size: {720, 480}
        Connected Screens:
        (1) LCD:
            Screen ID: 1
            Name: LCD
            Unique ID: PurpleMain
            Screen Type: Integrated
            Pixel Size: {1206, 2622}
        (2) TVOut:
            Screen ID: 2
            Name: TVOut
            Unique ID: PurpleTVOut
            Screen Type: TVOut
            Pixel Size: {720, 480}
        """

    private let phoneOnlySample = """
        Creatable Screen Properties:
        (101) CarPlay:
            Screen ID: 101
            Screen Type: CarPlay
            Pixel Size: {720, 480}
        Connected Screens:
        (1) LCD:
            Screen ID: 1
            Screen Type: Integrated
            Pixel Size: {1206, 2622}
        """

    @Test func `isCarPlayConnected is true when Connected Screens lists TVOut`() {
        #expect(SimctlIOEnumerate.isCarPlayConnected(connectedSample))
    }

    @Test func `isCarPlayConnected ignores creatable-only CarPlay`() {
        #expect(!SimctlIOEnumerate.isCarPlayConnected(phoneOnlySample))
    }

    @Test func `connectedScreens parses live screen ids and sizes`() {
        let screens = SimctlIOEnumerate.connectedScreens(from: connectedSample)
        #expect(screens.count == 2)
        #expect(screens[0].screenId == 1)
        #expect(screens[0].screenType == .integrated)
        #expect(screens[0].size == Size(width: 1206, height: 2622))
        #expect(screens[1].screenId == 2)
        #expect(screens[1].screenType == .tvOut)
        #expect(screens[1].size == Size(width: 720, height: 480))
    }

    @Test func `connectedCarPlay picks TVOut over creatable 101`() {
        let carPlay = SimctlIOEnumerate.connectedCarPlay(from: connectedSample)
        #expect(carPlay?.screenId == 2)
        #expect(carPlay?.screenType == .tvOut)
    }

    @Test func `connectedCarPlay is nil when only the phone is connected`() {
        #expect(SimctlIOEnumerate.connectedCarPlay(from: phoneOnlySample) == nil)
    }
}
