import Foundation
import Accelerate
import CoreVideo
import IOSurface

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
