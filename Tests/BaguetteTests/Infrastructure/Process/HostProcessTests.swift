import Foundation
import Testing
@testable import BaguetteCore

@Suite("HostProcess")
struct HostProcessTests {
    @Test func `captures merged output and exit status`() throws {
        let result = try HostProcess.capture(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf stdout; printf stderr >&2; exit 7"]
        )

        #expect(String(data: result.output, encoding: .utf8) == "stdoutstderr")
        #expect(result.status == 7)
    }
}
