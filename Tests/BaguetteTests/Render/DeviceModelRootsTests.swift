import Foundation
import Testing

@testable import BaguetteCore

@Suite("DeviceModelRoots")
struct DeviceModelRootsTests {

    @Test func `omits the bundled Models3D root when no resource bundle is present`() {
        let roots = DeviceModelRoots.standard(environment: [:], bundle: nil)
        #expect(!roots.contains { $0.path.hasSuffix("Models3D") })
    }

    @Test func `includes the bundled Models3D root when a resource bundle is present`() {
        let roots = DeviceModelRoots.standard(environment: [:], bundle: .main)
        #expect(roots.contains { $0.path.hasSuffix("Models3D") })
    }

    @Test func `puts the BAGUETTE_3D_MODEL_DIR override first`() {
        let roots = DeviceModelRoots.standard(
            environment: ["BAGUETTE_3D_MODEL_DIR": "/custom/models"],
            bundle: nil
        )
        #expect(roots.first == URL(fileURLWithPath: "/custom/models", isDirectory: true))
    }
}
