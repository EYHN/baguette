import Testing
@testable import BaguetteCore

/// Wire / CLI tokens map onto display kinds. Unknown tokens stay nil so
/// App can default to phone without Domain inventing a fallback.
@Suite("DisplayKind")
struct DisplayKindTests {

    @Test func `parses phone from query case-insensitively`() {
        #expect(DisplayKind.parse(query: "phone") == .phone)
        #expect(DisplayKind.parse(query: "PHONE") == .phone)
        #expect(DisplayKind.parse(query: "Phone") == .phone)
    }

    @Test func `parses carplay from query case-insensitively`() {
        #expect(DisplayKind.parse(query: "carplay") == .carPlay)
        #expect(DisplayKind.parse(query: "CarPlay") == .carPlay)
        #expect(DisplayKind.parse(query: "CARPLAY") == .carPlay)
    }

    @Test func `rejects unknown or empty query tokens`() {
        #expect(DisplayKind.parse(query: "tv") == nil)
        #expect(DisplayKind.parse(query: "") == nil)
        #expect(DisplayKind.parse(query: nil) == nil)
    }

    @Test func `parses phone and carplay from cli flags`() {
        #expect(DisplayKind.parse(cliFlag: "phone") == .phone)
        #expect(DisplayKind.parse(cliFlag: "carplay") == .carPlay)
        #expect(DisplayKind.parse(cliFlag: "CARPLAY") == .carPlay)
        #expect(DisplayKind.parse(cliFlag: "external") == nil)
        #expect(DisplayKind.parse(cliFlag: nil) == nil)
    }
}
