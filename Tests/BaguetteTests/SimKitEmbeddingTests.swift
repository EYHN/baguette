import Testing
@testable import BaguetteCore

@Suite("SimKitEmbedding")
struct SimKitEmbeddingTests {
    @Test func embeddedRuntimeRemainsAvailableAsALibrary() {
        #expect(BaguetteCoreHarness(deviceSetPath: "/tmp/test-devices").deviceSetPath == "/tmp/test-devices")
    }
}
