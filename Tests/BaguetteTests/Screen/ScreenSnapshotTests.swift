import Testing
import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import IOSurface
import Mockable
@testable import BaguetteCore

/// The SimulatorKit call that hands over a framebuffer is integration-
/// only, but everything `ScreenSnapshot` does around it is not: the
/// single-shot race between the frame callback, the timeout timer, and a
/// throwing `start`, plus the size / fit / format the caller asked for.
/// `MockScreen` stands in for the simulator and a host-allocated
/// `IOSurface` stands in for the framebuffer.
@Suite("ScreenSnapshot")
struct ScreenSnapshotTests {

    @Test func `a captured frame comes back as JPEG at the screen's own size`() async throws {
        let surface = try #require(makeSurface(width: 120, height: 60))
        let screen = MockScreen()
        given(screen).start(onFrame: .any, onMetadata: .any).willProduce { onFrame, _ in onFrame(surface) }
        given(screen).stop().willReturn(())

        let bytes = try await ScreenSnapshot.capture(screen: screen)

        #expect(bytes.prefix(2) == Data([0xFF, 0xD8]))
        #expect(try decoded(bytes) == CGSize(width: 120, height: 60))
    }

    @Test func `a requested size resizes the captured frame`() async throws {
        let surface = try #require(makeSurface(width: 120, height: 60))
        let screen = MockScreen()
        given(screen).start(onFrame: .any, onMetadata: .any).willProduce { onFrame, _ in onFrame(surface) }
        given(screen).stop().willReturn(())

        let bytes = try await ScreenSnapshot.capture(
            screen: screen,
            size: try CaptureSize.parse("40x80"), fit: .contain, background: "#000000"
        )

        #expect(try decoded(bytes) == CGSize(width: 40, height: 80))
    }

    @Test func `a PNG capture carries the PNG signature`() async throws {
        let surface = try #require(makeSurface(width: 40, height: 20))
        let screen = MockScreen()
        given(screen).start(onFrame: .any, onMetadata: .any).willProduce { onFrame, _ in onFrame(surface) }
        given(screen).stop().willReturn(())

        let bytes = try await ScreenSnapshot.capture(screen: screen, format: .png)

        #expect(bytes.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    @Test func `a screen that never delivers a frame times out`() async throws {
        let screen = MockScreen()
        given(screen).start(onFrame: .any, onMetadata: .any).willReturn(())
        given(screen).stop().willReturn(())

        await #expect(throws: ScreenSnapshot.Failure.timeout) {
            _ = try await ScreenSnapshot.capture(screen: screen, timeout: 0.05)
        }
    }

    @Test func `a screen that refuses to open surfaces its own error`() async throws {
        let screen = MockScreen()
        given(screen).start(onFrame: .any, onMetadata: .any).willThrow(SnapshotTestError.notBooted)
        given(screen).stop().willReturn(())

        await #expect(throws: SnapshotTestError.notBooted) {
            _ = try await ScreenSnapshot.capture(screen: screen)
        }
    }
}

private enum SnapshotTestError: Error, Equatable { case notBooted }

/// A host-allocated BGRA surface — same shape as the one SimulatorKit
/// hands over, without needing a booted simulator.
private func makeSurface(width: Int, height: Int) -> IOSurface? {
    IOSurface(properties: [
        .width: width,
        .height: height,
        .bytesPerElement: 4,
        .bytesPerRow: width * 4,
        .pixelFormat: kCVPixelFormatType_32BGRA,
        .allocSize: width * height * 4,
    ])
}

private func decoded(_ data: Data) throws -> CGSize {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return CGSize(width: image.width, height: image.height)
}
