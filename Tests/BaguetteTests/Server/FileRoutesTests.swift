import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// Handler-level coverage for the file-upload route. We test the pure
/// dispatch helper (`Server.addFile`) rather than the Hummingbird
/// `Response` wrapper — every branch driven with `MockSimulators` +
/// `MockApps` / `MockPhotoLibrary`.
///
/// `addFile` is the thin "which collection?" router: an app file goes
/// to `apps().install`, media to `photos().add`, and anything with no
/// home on a simulator is refused out loud (never silently dropped).
/// Classification is by extension, so the tests pass plain paths — no
/// bytes need exist on disk.
@Suite("Server file routes")
struct FileRoutesTests {

    @Test func `an .ipa is installed through the apps collection`() async {
        let host = MockSimulators()
        let sim = MockSimulator()
        let apps = MockApps()
        given(host).find(udid: .value("U")).willReturn(sim)
        given(sim).apps().willReturn(apps)
        given(apps).install(.any).willReturn(())

        let outcome = await Server.addFile(
            udid: "U", path: URL(fileURLWithPath: "/tmp/up/MyApp.ipa"), simulators: host
        )
        #expect(outcome == .installed)
        verify(apps).install(.value(AppBundle(path: URL(fileURLWithPath: "/tmp/up/MyApp.ipa")))).called(1)
    }

    @Test func `a photo is added through the photo library`() async {
        let host = MockSimulators()
        let sim = MockSimulator()
        let photos = MockPhotoLibrary()
        given(host).find(udid: .value("U")).willReturn(sim)
        given(sim).photos().willReturn(photos)
        given(photos).add(.any).willReturn(())

        let outcome = await Server.addFile(
            udid: "U", path: URL(fileURLWithPath: "/tmp/up/shot.png"), simulators: host
        )
        #expect(outcome == .added)
        verify(photos).add(.value(MediaItem(path: URL(fileURLWithPath: "/tmp/up/shot.png")))).called(1)
    }

    @Test func `a file with no home on a simulator is refused`() async {
        let host = MockSimulators()
        let sim = MockSimulator()
        given(host).find(udid: .value("U")).willReturn(sim)

        let outcome = await Server.addFile(
            udid: "U", path: URL(fileURLWithPath: "/tmp/up/notes.pdf"), simulators: host
        )
        #expect(outcome == .unsupported(ext: "pdf"))
    }

    @Test func `an unknown udid is reported`() async {
        let host = MockSimulators()
        given(host).find(udid: .value("ghost")).willReturn(nil)
        let outcome = await Server.addFile(
            udid: "ghost", path: URL(fileURLWithPath: "/tmp/up/MyApp.ipa"), simulators: host
        )
        #expect(outcome == .unknownDevice)
    }

    @Test func `a zipped .app is installed through the apps collection as an archive`() async {
        let host = MockSimulators()
        let sim = MockSimulator()
        let apps = MockApps()
        given(host).find(udid: .value("U")).willReturn(sim)
        given(sim).apps().willReturn(apps)
        given(apps).install(archive: .any).willReturn(())

        let outcome = await Server.addFile(
            udid: "U", path: URL(fileURLWithPath: "/tmp/up/MyApp.app.zip"), simulators: host
        )
        #expect(outcome == .installed)
        verify(apps).install(archive: .value(AppArchive(path: URL(fileURLWithPath: "/tmp/up/MyApp.app.zip")))).called(1)
    }

    @Test func `a zip with no app inside is refused with the reason`() async {
        let host = MockSimulators()
        let sim = MockSimulator()
        let apps = MockApps()
        given(host).find(udid: .value("U")).willReturn(sim)
        given(sim).apps().willReturn(apps)
        given(apps).install(archive: .any).willThrow(AppsError.noAppInArchive)

        let outcome = await Server.addFile(
            udid: "U", path: URL(fileURLWithPath: "/tmp/up/docs.zip"), simulators: host
        )
        #expect(outcome == .badArchive(reason: "no single .app bundle at the top level of the zip"))
    }

    @Test func `a corrupt zip is refused with the extract failure`() async {
        let host = MockSimulators()
        let sim = MockSimulator()
        let apps = MockApps()
        given(host).find(udid: .value("U")).willReturn(sim)
        given(sim).apps().willReturn(apps)
        given(apps).install(archive: .any).willThrow(AppsError.extractFailed(status: 2))

        let outcome = await Server.addFile(
            udid: "U", path: URL(fileURLWithPath: "/tmp/up/broken.zip"), simulators: host
        )
        #expect(outcome == .badArchive(reason: "ditto -x -k exited 2 (corrupt zip?)"))
    }

    @Test func `a zip that inflates past the extraction cap is refused with the reason`() async {
        let host = MockSimulators()
        let sim = MockSimulator()
        let apps = MockApps()
        given(host).find(udid: .value("U")).willReturn(sim)
        given(sim).apps().willReturn(apps)
        given(apps).install(archive: .any)
            .willThrow(AppsError.archiveTooLarge(bytes: 8_589_934_592, limit: 4_294_967_296))

        let outcome = await Server.addFile(
            udid: "U", path: URL(fileURLWithPath: "/tmp/up/bomb.zip"), simulators: host
        )
        #expect(outcome == .badArchive(
            reason: "archive inflates to 8589934592 bytes, over the 4294967296-byte cap (zip bomb?)"
        ))
    }

    @Test func `a simctl failure on the archive path surfaces as dispatchFailed`() async {
        let host = MockSimulators()
        let sim = MockSimulator()
        let apps = MockApps()
        given(host).find(udid: .value("U")).willReturn(sim)
        given(sim).apps().willReturn(apps)
        given(apps).install(archive: .any).willThrow(AppsError.installFailed(status: 1))

        let outcome = await Server.addFile(
            udid: "U", path: URL(fileURLWithPath: "/tmp/up/MyApp.app.zip"), simulators: host
        )
        #expect(outcome == .dispatchFailed)
    }

    @Test func `a simctl failure surfaces as dispatchFailed`() async {
        let host = MockSimulators()
        let sim = MockSimulator()
        let apps = MockApps()
        given(host).find(udid: .value("U")).willReturn(sim)
        given(sim).apps().willReturn(apps)
        given(apps).install(.any).willThrow(AppsError.installFailed(status: 1))

        let outcome = await Server.addFile(
            udid: "U", path: URL(fileURLWithPath: "/tmp/up/MyApp.ipa"), simulators: host
        )
        #expect(outcome == .dispatchFailed)
    }
}
