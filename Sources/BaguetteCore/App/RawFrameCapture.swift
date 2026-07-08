import Foundation
import IOSurface

/// Embedding API for hosts that link BaguetteCore directly (e.g. the SimKit
/// daemon): raw I420 frames delivered as borrowed pointers over a callback —
/// no server, no socket, no wire envelope. The shortest possible path from
/// the simulator compositor to an external encoder.
///
/// Frames are converted (BGRA → limited-range BT.601 I420) only when the
/// compositor delivers a new surface; while the screen is static a pump
/// re-emits the previously converted payload every `idleInterval` without
/// re-scaling or re-converting, so downstream encoders can always answer
/// keyframe requests.
///
/// The capture object also owns an input dispatcher for the same simulator,
/// since embedded streaming sessions route gestures alongside frames.
public final class RawFrameCapture: @unchecked Sendable {
    /// Borrowed view of one converted frame. Valid only for the duration of
    /// the callback; copy what you need.
    public struct Payload {
        public let width: Int
        public let height: Int
        public let captureMicros: UInt64
        /// Tightly packed planes: Y (w*h), U (w/2*h/2), V (w/2*h/2).
        public let planes: UnsafeRawBufferPointer
    }

    private let udid: String
    private let simulators: CoreSimulators
    private let scaler = Scaler()
    private let converter = BGRAToI420Converter()
    private let queue = DispatchQueue(label: "baguette.rawcapture", qos: .userInteractive)

    private var screen: (any Screen)?
    private var dispatcher: GestureDispatcher?
    private var pump: DispatchSourceTimer?
    private var idleInterval: TimeInterval = 0.25
    private var scale = 1
    private var onFrame: (@Sendable (Payload) -> Void)?

    /// Last converted payload (header stripped), re-emitted by the pump.
    private var lastPlanes = Data()
    private var lastWidth = 0
    private var lastHeight = 0

    public init(udid: String, deviceSetPath: String? = nil) {
        self.udid = udid
        self.simulators = CoreSimulators(deviceSetPath: deviceSetPath)
    }

    /// Starts frame delivery. `onFrame` runs on the capture queue.
    public func start(
        scale: Int = 1,
        idleInterval: TimeInterval = 0.25,
        onFrame: @escaping @Sendable (Payload) -> Void
    ) throws {
        guard let sim = simulators.find(udid: udid) else {
            throw BaguetteCoreError.notFound("Device \(udid) not found")
        }
        self.scale = max(1, scale)
        self.idleInterval = max(0.05, idleInterval)
        self.onFrame = onFrame
        let screen = sim.screen()
        self.screen = screen
        try screen.start { [weak self] surface in
            self?.handle(surface)
        }
    }

    public func stop() {
        // Stop the screen first so no new frames get enqueued, then flush
        // the capture queue and clear the callback on it — after this
        // returns, the host may safely free its callback context.
        screen?.stop()
        screen = nil
        queue.sync {
            pump?.cancel()
            pump = nil
            lastPlanes = Data()
            onFrame = nil
        }
    }

    /// Dispatches one JSON gesture line (same grammar as the stream WS /
    /// stdin control channel) and returns the ack JSON. The dispatcher is
    /// created lazily and reused, so per-event overhead is one JSON parse.
    public func dispatchInput(line: String) -> String {
        if dispatcher == nil {
            guard let sim = simulators.find(udid: udid) else {
                return #"{"ok":false,"error":"unknown udid"}"#
            }
            dispatcher = GestureDispatcher(input: sim.input())
        }
        guard let dispatcher else {
            return #"{"ok":false,"error":"input unavailable"}"#
        }
        return dispatcher.dispatch(line: line)
    }

    // Debug counters (SIMKIT_RTC_DEBUG): compositor callback rate vs
    // conversion cost, printed once per second to stderr.
    private let debugEnabled =
        ProcessInfo.processInfo.environment["SIMKIT_RTC_DEBUG"] != nil
    private var dbgWindowStart = DispatchTime.now()
    private var dbgCallbacks = 0
    private var dbgConvertNanos: UInt64 = 0

    private func handle(_ surface: IOSurface) {
        queue.async { [weak self] in
            guard let self else { return }
            let t0 = DispatchTime.now()
            self.convertAndEmit(surface)
            if self.debugEnabled {
                self.dbgCallbacks += 1
                self.dbgConvertNanos += DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds
                let elapsed = DispatchTime.now().uptimeNanoseconds
                    - self.dbgWindowStart.uptimeNanoseconds
                if elapsed >= 1_000_000_000 {
                    let secs = Double(elapsed) / 1e9
                    let rate = Double(self.dbgCallbacks) / secs
                    let avgMs = Double(self.dbgConvertNanos) / Double(self.dbgCallbacks) / 1e6
                    FileHandle.standardError.write(Data(String(
                        format: "[baguette capture] compositor %.1f cb/s, convert avg %.2f ms\n",
                        rate, avgMs
                    ).utf8))
                    self.dbgWindowStart = DispatchTime.now()
                    self.dbgCallbacks = 0
                    self.dbgConvertNanos = 0
                }
            }
            self.armPump()
        }
    }

    /// Scale + convert a fresh compositor surface, cache the result, emit.
    /// At scale 1 the conversion reads the IOSurface directly (locked
    /// read-only) — no intermediate BGRA copy or GPU round trip.
    private func convertAndEmit(_ surface: IOSurface) {
        let payload: Data?
        if scale <= 1 {
            IOSurfaceLock(surface, .readOnly, nil)
            payload = converter.convert(
                base: IOSurfaceGetBaseAddress(surface),
                rowBytes: IOSurfaceGetBytesPerRow(surface),
                width: IOSurfaceGetWidth(surface),
                height: IOSurfaceGetHeight(surface)
            )
            IOSurfaceUnlock(surface, .readOnly, nil)
        } else {
            guard let pb = scaler.downscale(surface, scale: scale) else { return }
            payload = converter.convert(pb)
        }
        guard let payload else { return }
        // Converter output is [16-byte header][planes]; strip the header —
        // the embedding API carries dimensions natively.
        let headerSize = 16
        guard payload.count > headerSize else { return }
        lastWidth = Int(readBigEndianU32(payload, at: 0))
        lastHeight = Int(readBigEndianU32(payload, at: 4))
        lastPlanes = payload.subdata(in: headerSize..<payload.count)
        emitCached()
    }

    /// Emits the cached planes without conversion (used for both fresh
    /// frames right after conversion and idle pump re-emits).
    private func emitCached() {
        guard !lastPlanes.isEmpty, let onFrame else { return }
        let width = lastWidth
        let height = lastHeight
        let micros = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        lastPlanes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            onFrame(Payload(width: width, height: height, captureMicros: micros, planes: raw))
        }
    }

    /// Live frames keep pushing the timer back; only a real idle gap lets
    /// it tick and re-emit the cached payload.
    private func armPump() {
        pump?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + idleInterval,
            repeating: idleInterval,
            leeway: .milliseconds(10)
        )
        timer.setEventHandler { [weak self] in self?.emitCached() }
        timer.resume()
        pump = timer
    }

    private func readBigEndianU32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: offset..<(offset + 4))
        }
        return UInt32(bigEndian: value)
    }
}
