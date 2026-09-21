import Testing
import Foundation
@testable import BaguetteCore

@Suite("CameraFrame")
struct CameraFrameTests {
    @Test func `accepts a well-formed BGRA frame`() throws {
        let pixels = Data(count: 4 * 4 * 4)  // 4×4 BGRA
        let frame = try CameraFrame(
            sequence: 1, timestampMs: 0, width: 4, height: 4, pixels: pixels
        )
        #expect(frame.expectedPixelByteCount == 4 * 4 * 4)
        #expect(frame.pixels == pixels)
    }

    @Test func `rejects pixel data with wrong length`() {
        #expect(throws: CameraFrameError.pixelDataSizeMismatch(expected: 64, got: 8)) {
            _ = try CameraFrame(
                sequence: 1, timestampMs: 0, width: 4, height: 4, pixels: Data(count: 8)
            )
        }
    }

    @Test func `rejects frames larger than the shared canvas`() {
        // 1281 × 1280 × 4 — one pixel wider than the canvas cap.
        let oversize = 1281 * 1280 * 4
        #expect(throws: CameraFrameError.frameTooLarge(width: 1281, height: 1280)) {
            _ = try CameraFrame(
                sequence: 1, timestampMs: 0, width: 1281, height: 1280, pixels: Data(count: oversize)
            )
        }
    }

    @Test func `rejects zero dimensions`() {
        #expect(throws: CameraFrameError.invalidDimensions(width: 0, height: 4)) {
            _ = try CameraFrame(
                sequence: 1, timestampMs: 0, width: 0, height: 4, pixels: Data()
            )
        }
    }

    @Test func `resequenced swaps the sequence but preserves the pixels`() throws {
        let pixels = Data(repeating: 0x7F, count: 16)  // 2×2 BGRA
        let seed = try CameraFrame(
            sequence: 1, timestampMs: 40, width: 2, height: 2, pixels: pixels
        )
        let bumped = seed.resequenced(7)
        #expect(bumped.sequence == 7)
        #expect(bumped.width == 2)
        #expect(bumped.height == 2)
        #expect(bumped.timestampMs == 40)
        #expect(bumped.pixels == pixels)
    }
}
