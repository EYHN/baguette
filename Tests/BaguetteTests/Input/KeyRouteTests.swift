import Testing
@testable import Baguette

@Suite("KeyRoute")
struct KeyRouteTests {
    @Test func anIOS27RuntimeTakesKeysFromTheKeyboardService() {
        #expect(KeyRoute.choose(runtimeMajor: 27) == .keyboardService)
        #expect(KeyRoute.choose(runtimeMajor: 28) == .keyboardService)
    }

    @Test func olderRuntimesKeepTheTouchTarget() {
        #expect(KeyRoute.choose(runtimeMajor: 26) == .touchTarget)
        #expect(KeyRoute.choose(runtimeMajor: 18) == .touchTarget)
        #expect(KeyRoute.choose(runtimeMajor: nil) == .touchTarget)
    }
}
