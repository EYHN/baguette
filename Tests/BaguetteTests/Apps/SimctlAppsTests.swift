import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// Orchestration coverage for `SimctlApps` — argv assembly + the
/// `Subprocess` exit handshake. The irreducible `xcrun` spawn lives in
/// `HostSubprocess` (integration-only), so every branch is driven
/// through `MockSubprocess`.
@Suite("SimctlApps")
struct SimctlAppsTests {

    final class Captures: @unchecked Sendable {
        var executable: URL?
        var arguments: [String]?
        var ran = false
    }

    private func makeApps(exitCode: Int32 = 0) -> (SimctlApps, Captures) {
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
        return (SimctlApps(udid: "U", subprocess: sub), captures)
    }

    @Test func `install spawns xcrun simctl install with the app path`() async throws {
        let (apps, captures) = makeApps()
        try await apps.install(AppBundle(path: URL(fileURLWithPath: "/tmp/MyApp.ipa")))

        #expect(captures.executable == URL(fileURLWithPath: "/usr/bin/xcrun"))
        #expect(captures.arguments == ["simctl", "install", "U", "/tmp/MyApp.ipa"])
    }

    @Test func `a non-zero simctl exit propagates as an install failure`() async {
        let (apps, _) = makeApps(exitCode: 3)
        var caught: AppsError?
        do {
            try await apps.install(AppBundle(path: URL(fileURLWithPath: "/tmp/MyApp.ipa")))
        } catch {
            caught = error as? AppsError
        }
        #expect(caught == .installFailed(status: 3))
    }

    // MARK: archives — extract → locate → install

    /// Per-call capture for the two-subprocess archive flow: the ditto
    /// stub plays the extraction's side effect (materialising entries
    /// in the destination dir), the xcrun stub records the install argv.
    final class ArchiveCaptures: @unchecked Sendable {
        var extractionDir: String?
        var installArguments: [String]?
    }

    private func makeArchiveApps(
        dittoExit: Int32 = 0,
        installExit: Int32 = 0,
        extractedEntries: [String] = ["MyApp.app"],
        payloadBytes: Int = 0,
        maxExtractedBytes: Int64 = 4 << 30
    ) -> (SimctlApps, ArchiveCaptures) {
        let sub = MockSubprocess()
        let captures = ArchiveCaptures()
        given(sub).run(
            executable: .any, arguments: .any, onBytes: .any, onExit: .any
        ).willProduce { exe, args, _, onExit in
            if exe == URL(fileURLWithPath: "/usr/bin/ditto") {
                let dest = args[args.count - 1]
                captures.extractionDir = dest
                for entry in extractedEntries {
                    try? FileManager.default.createDirectory(
                        atPath: dest + "/" + entry, withIntermediateDirectories: true
                    )
                    if payloadBytes > 0 {
                        FileManager.default.createFile(
                            atPath: dest + "/" + entry + "/payload",
                            contents: Data(count: payloadBytes)
                        )
                    }
                }
                onExit(dittoExit)
            } else {
                captures.installArguments = args
                onExit(installExit)
            }
        }
        given(sub).terminate().willReturn()
        return (
            SimctlApps(udid: "U", subprocess: sub, maxExtractedBytes: maxExtractedBytes),
            captures
        )
    }

    @Test func `an archive is extracted with ditto and the inner app installed`() async throws {
        let (apps, captures) = makeArchiveApps()
        try await apps.install(archive: AppArchive(path: URL(fileURLWithPath: "/tmp/up/MyApp.app.zip")))

        let dir = try #require(captures.extractionDir)
        let argv = try #require(captures.installArguments)
        #expect(argv == ["simctl", "install", "U", dir + "/MyApp.app"])
    }

    @Test func `the extraction directory is cleaned up after the install`() async throws {
        let (apps, captures) = makeArchiveApps()
        try await apps.install(archive: AppArchive(path: URL(fileURLWithPath: "/tmp/up/MyApp.app.zip")))

        let dir = try #require(captures.extractionDir)
        #expect(!FileManager.default.fileExists(atPath: dir))
    }

    @Test func `a non-zero ditto exit propagates as an extract failure`() async {
        let (apps, _) = makeArchiveApps(dittoExit: 2)
        var caught: AppsError?
        do {
            try await apps.install(archive: AppArchive(path: URL(fileURLWithPath: "/tmp/up/broken.zip")))
        } catch {
            caught = error as? AppsError
        }
        #expect(caught == .extractFailed(status: 2))
    }

    @Test func `an archive with no app inside is refused`() async {
        let (apps, captures) = makeArchiveApps(extractedEntries: ["readme.txt"])
        var caught: AppsError?
        do {
            try await apps.install(archive: AppArchive(path: URL(fileURLWithPath: "/tmp/up/docs.zip")))
        } catch {
            caught = error as? AppsError
        }
        #expect(caught == .noAppInArchive)
        #expect(captures.installArguments == nil)
    }

    @Test func `an archive declaring more than the cap is refused before extraction`() async throws {
        let (apps, captures) = makeArchiveApps(maxExtractedBytes: 16)
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bomb-\(UUID().uuidString).app.zip")
        try ZipFixture.archive(declaring: [("MyApp.app/MyApp", 64)]).write(to: zipURL)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        var caught: AppsError?
        do {
            try await apps.install(archive: AppArchive(path: zipURL))
        } catch {
            caught = error as? AppsError
        }
        #expect(caught == .archiveTooLarge(bytes: 64, limit: 16))
        #expect(captures.extractionDir == nil)   // ditto never spawned
        #expect(captures.installArguments == nil)
    }

    @Test func `an archive declaring less than the cap proceeds to extraction`() async throws {
        let (apps, captures) = makeArchiveApps(maxExtractedBytes: 1024)
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ok-\(UUID().uuidString).app.zip")
        try ZipFixture.archive(declaring: [("MyApp.app/MyApp", 64)]).write(to: zipURL)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        try await apps.install(archive: AppArchive(path: zipURL))
        #expect(captures.extractionDir != nil)
        #expect(captures.installArguments != nil)
    }

    @Test func `an archive that inflates past the extraction cap is refused before install`() async {
        let (apps, captures) = makeArchiveApps(payloadBytes: 64, maxExtractedBytes: 16)
        var caught: AppsError?
        do {
            try await apps.install(archive: AppArchive(path: URL(fileURLWithPath: "/tmp/up/bomb.zip")))
        } catch {
            caught = error as? AppsError
        }
        #expect(caught == .archiveTooLarge(bytes: 64, limit: 16))
        #expect(captures.installArguments == nil)
        if let dir = captures.extractionDir {
            #expect(!FileManager.default.fileExists(atPath: dir))
        }
    }

    @Test func `an archive within the extraction cap still installs`() async throws {
        let (apps, captures) = makeArchiveApps(payloadBytes: 8, maxExtractedBytes: 16)
        try await apps.install(archive: AppArchive(path: URL(fileURLWithPath: "/tmp/up/MyApp.app.zip")))
        #expect(captures.installArguments != nil)
    }

    @Test func `a simctl failure after extraction propagates as an install failure`() async {
        let (apps, _) = makeArchiveApps(installExit: 5)
        var caught: AppsError?
        do {
            try await apps.install(archive: AppArchive(path: URL(fileURLWithPath: "/tmp/up/MyApp.app.zip")))
        } catch {
            caught = error as? AppsError
        }
        #expect(caught == .installFailed(status: 5))
    }
}
