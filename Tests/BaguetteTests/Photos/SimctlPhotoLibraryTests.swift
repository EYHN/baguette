import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// Orchestration coverage for `SimctlPhotoLibrary` — argv assembly +
/// the `Subprocess` exit handshake. The irreducible `xcrun` spawn lives
/// in `HostSubprocess` (integration-only), so every branch is driven
/// through `MockSubprocess`.
@Suite("SimctlPhotoLibrary")
struct SimctlPhotoLibraryTests {

    final class Captures: @unchecked Sendable {
        var executable: URL?
        var arguments: [String]?
        var ran = false
    }

    private func makeLibrary(exitCode: Int32 = 0) -> (SimctlPhotoLibrary, Captures) {
        let sub = MockSubprocess()
        let captures = Captures()
        given(sub).run(
            executable: .any, arguments: .any, onBytes: .any, onExit: .any
        ).willProduce { exe, args, _, onExit in
            captures.ran = true
            captures.executable = exe
            captures.arguments = args
            onExit(exitCode)
        }
        given(sub).terminate().willReturn()
        return (SimctlPhotoLibrary(udid: "U", subprocess: sub), captures)
    }

    @Test func `add spawns xcrun simctl addmedia with the media path`() async throws {
        let (library, captures) = makeLibrary()
        try await library.add(MediaItem(path: URL(fileURLWithPath: "/tmp/clip.mov")))

        #expect(captures.executable == URL(fileURLWithPath: "/usr/bin/xcrun"))
        #expect(captures.arguments == ["simctl", "addmedia", "U", "/tmp/clip.mov"])
    }

    @Test func `a non-zero simctl exit propagates as an add failure`() async {
        let (library, _) = makeLibrary(exitCode: 5)
        var caught: PhotoLibraryError?
        do {
            try await library.add(MediaItem(path: URL(fileURLWithPath: "/tmp/clip.mov")))
        } catch {
            caught = error as? PhotoLibraryError
        }
        #expect(caught == .addFailed(status: 5))
    }
}
