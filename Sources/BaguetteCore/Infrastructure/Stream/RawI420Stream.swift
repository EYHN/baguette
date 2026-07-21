import Foundation
import Accelerate
import CoreVideo
import IOSurface

/// Raw I420 stream: uncompressed planar YUV 4:2:0 frames for consumers
/// that own the video encoder themselves (e.g. a WebRTC/LiveKit publisher
/// feeding frames into libwebrtc). Skipping the in-process H.264 encode
/// removes a full encode/decode round trip from the pipeline — the
/// consumer's encoder sees the pixels directly.
///
/// Driven by `screen` callbacks like AVCC: every SimulatorKit composite
/// is converted and emitted, preserving the simulator's real cadence. An
/// idle pump re-emits the last surface at `1/fps` so downstream encoders
/// always have a recent frame to answer keyframe requests with.
///
/// Wire envelope (via `AVCCEnvelope.rawFrame`, tag 0x06):
///   [u32 width][u32 height][u64 captureUnixMicros]
///   [Y w*h][U (w/2)*(h/2)][V (w/2)*(h/2)]      (big-endian header,
///                                               tightly packed planes,
///                                               even dimensions)
final class RawI420Stream: Stream, @unchecked Sendable {
    private(set) var config: StreamConfig
    private let sink: any FrameSink
    private let scaler = VideoFrameScaler()
    private let converter = BGRAToI420Converter()
    private let queue = DispatchQueue(label: "baguette.rawi420", qos: .userInteractive)

    private var screen: (any Screen)?
    private var lastSurface: IOSurface?
    private var pump: DispatchSourceTimer?

    init(config: StreamConfig, sink: any FrameSink) {
        self.config = config
        self.sink = sink
    }

    func start(on screen: any Screen) throws {
        log("start: format=raw fps=\(config.fps) scale=\(config.scale)")
        self.screen = screen
        try screen.start { [weak self] surface in
            self?.handle(surface)
        }
    }

    func stop() {
        pump?.cancel()
        pump = nil
        screen?.stop()
        screen = nil
        lastSurface = nil
    }

    func apply(_ newConfig: StreamConfig) {
        let old = config
        config = newConfig
        log("apply: fps \(old.fps)→\(newConfig.fps), scale \(old.scale)→\(newConfig.scale)")
    }

    /// Keyframes are the consumer-side encoder's concern; nothing to do.
    func requestKeyframe() {}
    /// No JPEG seed on the raw wire; the first frame paints itself.
    func requestSnapshot() {}

    /// Re-arms the idle pump to fire `1/fps` from now — same pattern as
    /// AVCCStream: live callbacks keep pushing the timer back, only a
    /// real idle gap lets it tick and re-emit the last surface.
    private func armPump() {
        pump?.cancel()
        let interval = 1.0 / Double(max(1, config.fps))
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.pumpTick() }
        timer.resume()
        pump = timer
    }

    private func pumpTick() {
        guard let surface = lastSurface else { return }
        emit(surface)
    }

    private func handle(_ surface: IOSurface) {
        queue.async { [weak self] in
            self?.lastSurface = surface
            self?.emit(surface)
            self?.armPump()
        }
    }

    private func emit(_ surface: IOSurface) {
        // VideoFrameScaler always copies (even at scale=1) so we never read a
        // framebuffer SimulatorKit is recycling in place.
        guard let pb = scaler.scale(surface, by: config.scale) else { return }
        guard let payload = converter.convert(pb) else { return }
        sink.write(AVCCEnvelope.rawFrame(payload: payload))
    }
}

/// vImage-backed BGRA → planar I420 (limited-range BT.601) converter with
/// reused destination storage. SIMD conversion runs in a couple of
/// milliseconds at half resolution — cheap enough for 60 fps duplicates.
final class BGRAToI420Converter {
    private var conversion = vImage_ARGBToYpCbCr()
    private var conversionReady = false
    private var planes = Data()

    /// Returns the raw-frame payload (header + planes) or nil when the
    /// buffer can't be locked/converted.
    func convert(_ pixelBuffer: CVPixelBuffer) -> Data? {
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        return convert(
            base: base,
            rowBytes: CVPixelBufferGetBytesPerRow(pixelBuffer),
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
    }

    /// Pointer-based variant: converts a BGRA buffer the caller has already
    /// locked (e.g. an IOSurface base address) without any intermediate copy.
    func convert(base: UnsafeMutableRawPointer?, rowBytes: Int, width: Int, height: Int) -> Data? {
        guard prepareConversion(), let base else { return nil }

        // I420 needs even dimensions; crop a single row/column when odd.
        let width = width & ~1
        let height = height & ~1
        guard width >= 2, height >= 2 else { return nil }

        let ySize = width * height
        let chromaWidth = width / 2
        let chromaHeight = height / 2
        let chromaSize = chromaWidth * chromaHeight
        let headerSize = 16
        let total = headerSize + ySize + 2 * chromaSize
        if planes.count != total {
            planes = Data(count: total)
        }

        let captureMicros = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        var ok = false
        planes.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            guard let out = raw.baseAddress else { return }
            writeBigEndian(UInt32(width), to: out, at: 0)
            writeBigEndian(UInt32(height), to: out, at: 4)
            writeBigEndian(captureMicros, to: out, at: 8)

            var src = vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: base),
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: rowBytes
            )
            var yp = vImage_Buffer(
                data: out + headerSize,
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: width
            )
            var cb = vImage_Buffer(
                data: out + headerSize + ySize,
                height: vImagePixelCount(chromaHeight),
                width: vImagePixelCount(chromaWidth),
                rowBytes: chromaWidth
            )
            var cr = vImage_Buffer(
                data: out + headerSize + ySize + chromaSize,
                height: vImagePixelCount(chromaHeight),
                width: vImagePixelCount(chromaWidth),
                rowBytes: chromaWidth
            )
            // Source is BGRA; the permute map lifts it into the ARGB
            // channel order the converter expects (A=3, R=2, G=1, B=0).
            let permuteMap: [UInt8] = [3, 2, 1, 0]
            let error = vImageConvert_ARGB8888To420Yp8_Cb8_Cr8(
                &src, &yp, &cb, &cr,
                &conversion, permuteMap, vImage_Flags(kvImageNoFlags)
            )
            ok = error == kvImageNoError
        }
        return ok ? planes : nil
    }

    /// ITU-R BT.601 RGB→YCbCr coefficients. Declared locally because the
    /// Accelerate global (`kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4`) is a C
    /// `var`, which Swift 6 rejects as non-concurrency-safe shared state.
    private static let bt601Matrix = vImage_ARGBToYpCbCrMatrix(
        R_Yp: 0.299, G_Yp: 0.587, B_Yp: 0.114,
        R_Cb: -0.1687, G_Cb: -0.3313, B_Cb_R_Cr: 0.5,
        G_Cr: -0.4187, B_Cr: -0.0813
    )

    private func prepareConversion() -> Bool {
        if conversionReady { return true }
        // Limited-range (video) BT.601, matching what WebRTC stacks assume
        // for I420 input.
        var pixelRange = vImage_YpCbCrPixelRange(
            Yp_bias: 16, CbCr_bias: 128,
            YpRangeMax: 235, CbCrRangeMax: 240,
            YpMax: 235, YpMin: 16,
            CbCrMax: 240, CbCrMin: 16
        )
        var matrix = Self.bt601Matrix
        let error = vImageConvert_ARGBToYpCbCr_GenerateConversion(
            &matrix,
            &pixelRange,
            &conversion,
            kvImageARGB8888,
            kvImage420Yp8_Cb8_Cr8,
            vImage_Flags(kvImageNoFlags)
        )
        conversionReady = error == kvImageNoError
        return conversionReady
    }

    private func writeBigEndian(_ value: UInt32, to base: UnsafeMutableRawPointer, at offset: Int) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { bytes in
            base.advanced(by: offset).copyMemory(from: bytes.baseAddress!, byteCount: 4)
        }
    }

    private func writeBigEndian(_ value: UInt64, to base: UnsafeMutableRawPointer, at offset: Int) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { bytes in
            base.advanced(by: offset).copyMemory(from: bytes.baseAddress!, byteCount: 8)
        }
    }
}
