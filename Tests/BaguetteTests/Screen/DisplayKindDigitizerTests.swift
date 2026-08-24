import Testing

@testable import BaguetteCore

@Suite("DisplayKind digitizer")
struct DisplayKindDigitizerTests {

    /// The phone's digitizer is part of the device and always there;
    /// asking the guest to build one would be asking for a second.
    @Test func `the phone plane needs no digitizer built for it`() {
        #expect(!DisplayKind.phone.needsExternalDigitizer)
    }

    @Test func `an external plane needs its digitizer built`() {
        #expect(DisplayKind.carPlay.needsExternalDigitizer)
    }
}
