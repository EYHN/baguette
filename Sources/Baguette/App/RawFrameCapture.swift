import Accelerate
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
        /// SimulatorKit `screenProperties.uiOrientation`: 1...4, or 0
        /// while the property is unavailable.
        public let uiOrientationRaw: UInt32
        /// Tightly packed planes: Y (w*h), U (w/2*h/2), V (w/2*h/2).
        public let planes: UnsafeRawBufferPointer
        /// Nil for a device with one display. A foldable's frame is a
        /// `DisplayCanvas` of all its panels, and this JSON says where each
        /// one is, which one the device is presenting on, and how each is
        /// turned; `uiOrientationRaw` is the presenting panel's.
        public let layoutJSON: String?
    }

    /// Conversion state kept per panel of a foldable, so a panel that has
    /// not drawn since its last conversion is not converted again.
    private final class PanelConversion {
        let converter = BGRAToI420Converter()
        var scaledPixels = Data()
        var scaleTemp = Data()
        var seed: UInt32?
    }
    private var panelConversions: [UInt32: PanelConversion] = [:]
    private var canvas: (layout: DisplayCanvas, planes: I420Canvas)?

    private let udid: String
    private let simulators: CoreSimulators
    private let converter = BGRAToI420Converter()
    /// Reused half-res BGRA storage + vImage scratch for the downscale path.
    private var scaledPixels = Data()
    private var scaleTemp = Data()
    private let queue = DispatchQueue(label: "baguette.rawcapture", qos: .userInteractive)

    private var screen: (any Screen)?
    /// The standing hinge subscription, foldables only. Its samples restate
    /// the layout, so a viewer hears the angle without polling.
    private var hingeWatch: (any HingeWatch)?
    private var dispatcher: GestureDispatcher?
    private var input: (any Input)?
    private var pump: DispatchSourceTimer?
    private var idleInterval: TimeInterval = 0.25
    private var scale = 1
    private var onFrame: (@Sendable (Payload) -> Void)?

    /// Last converted pixels plus independently changing screen metadata.
    private var payloadCache = RawFramePayloadCache()

    public init(udid: String, deviceSetPath: String? = nil) {
        self.udid = udid
        simulators = CoreSimulators(deviceSetPath: deviceSetPath)
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
        // Hosts may pump as fast as 120Hz to hold a constant output rate;
        // re-emits are cached-payload only, so the floor is just a guard.
        self.idleInterval = max(0.008, idleInterval)
        self.onFrame = onFrame
        if let core = sim as? CoreSimulator, core.folds {
            let hinge = sim.hinge()
            let initial = hinge.angle()?.degrees
            hingeWatch = hinge.watch { [weak self] angle in
                self?.queue.async {
                    guard let self else { return }
                    if self.payloadCache.update(hingeDegrees: angle.degrees) {
                        self.emitCached()
                    }
                }
            }
            if let initial {
                queue.async { [weak self] in
                    _ = self?.payloadCache.update(hingeDegrees: initial)
                }
            }
        }
        let screen = sim.screen()
        self.screen = screen
        // A foldable streams all its panels on one fixed canvas.
        (screen as? SimulatorKitScreen)?.onPanels = { [weak self] surfaces, presenting in
            self?.handle(surfaces, presenting: presenting)
        }
        try screen.start(
            onFrame: { [weak self] surface in
                self?.handle(surface)
            },
            onMetadata: { [weak self] metadata in
                self?.handle(metadata)
            }
        )
    }

    public func stop() {
        // Stop the screen first so no new frames get enqueued, then flush
        // the capture queue and clear the callback on it — after this
        // returns, the host may safely free its callback context.
        hingeWatch?.cancel()
        hingeWatch = nil
        screen?.stop()
        screen = nil
        queue.sync {
            pump?.cancel()
            pump = nil
            payloadCache.clear()
            panelConversions.removeAll()
            canvas = nil
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
            let input = sim.input()
            self.input = input
            dispatcher = GestureDispatcher(input: input)
        }
        guard let dispatcher, let input else {
            return #"{"ok":false,"error":"input unavailable"}"#
        }
        return DisplayAddress.dispatch(line, to: input, through: dispatcher)
    }

    /// Debug counters (SIMKIT_RTC_DEBUG): compositor callback rate vs
    /// conversion cost, printed once per second to stderr.
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

    private func handle(_ surfaces: [SimulatorKitScreen.PanelSurface], presenting: DisplayPanel?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.composeAndEmit(surfaces, presenting: presenting)
            self.armPump()
        }
    }

    /// Converts whichever panels have drawn since last time into their
    /// regions of the canvas, then emits the whole canvas.
    private func composeAndEmit(_ surfaces: [SimulatorKitScreen.PanelSurface], presenting: DisplayPanel?) {
        if canvas == nil {
            let panels = DisplayPanels(panels: surfaces.map(\.panel))
            guard let layout = DisplayCanvas.laying(out: panels, scale: scale) else { return }
            canvas = (layout, I420Canvas(width: layout.width, height: layout.height))
        }
        guard var current = canvas else { return }
        for item in surfaces {
            guard let region = current.layout.region(screenID: item.panel.screenID) else { continue }
            let state = panelConversions[item.panel.screenID] ?? PanelConversion()
            panelConversions[item.panel.screenID] = state
            let seed = IOSurfaceGetSeed(item.surface)
            guard state.seed != seed else { continue }
            IOSurfaceLock(item.surface, .readOnly, nil)
            let converted = scale <= 1
                ? state.converter.convert(
                    base: IOSurfaceGetBaseAddress(item.surface),
                    rowBytes: IOSurfaceGetBytesPerRow(item.surface),
                    width: IOSurfaceGetWidth(item.surface),
                    height: IOSurfaceGetHeight(item.surface)
                )
                : downscaleAndConvert(
                    item.surface, converter: state.converter,
                    scaledPixels: &state.scaledPixels, scaleTemp: &state.scaleTemp
                )
            IOSurfaceUnlock(item.surface, .readOnly, nil)
            let headerSize = 16
            guard let converted, converted.count > headerSize else { continue }
            state.seed = seed
            current.planes.draw(
                converted.subdata(in: headerSize ..< converted.count),
                width: Int(readBigEndianU32(converted, at: 0)),
                height: Int(readBigEndianU32(converted, at: 4)),
                at: region.rect
            )
        }
        canvas = current
        payloadCache.store(width: current.layout.width, height: current.layout.height, planes: current.planes.planes)
        payloadCache.update(canvas: current.layout, presenting: presenting)
        emitCached()
    }

    private func handle(_ metadata: ScreenMetadata) {
        queue.async { [weak self] in
            self?.payloadCache.update(metadata: metadata)
        }
    }

    /// Scale + convert a fresh compositor surface, cache the result, emit.
    /// The conversion reads the IOSurface directly (locked read-only); at
    /// scale > 1 a vImage CPU downscale into reused storage runs first —
    /// no CVPixelBuffer allocation, no CoreImage/GPU round trip.
    private func convertAndEmit(_ surface: IOSurface) {
        IOSurfaceLock(surface, .readOnly, nil)
        let payload: Data?
        if scale <= 1 {
            payload = converter.convert(
                base: IOSurfaceGetBaseAddress(surface),
                rowBytes: IOSurfaceGetBytesPerRow(surface),
                width: IOSurfaceGetWidth(surface),
                height: IOSurfaceGetHeight(surface)
            )
        } else {
            payload = downscaleAndConvert(surface)
        }
        IOSurfaceUnlock(surface, .readOnly, nil)
        guard let payload else { return }
        // Converter output is [16-byte header][planes]; strip the header —
        // the embedding API carries dimensions natively.
        let headerSize = 16
        guard payload.count > headerSize else { return }
        payloadCache.store(
            width: Int(readBigEndianU32(payload, at: 0)),
            height: Int(readBigEndianU32(payload, at: 4)),
            planes: payload.subdata(in: headerSize ..< payload.count)
        )
        emitCached()
    }

    /// vImage BGRA downscale (1/`scale` per axis) into reused storage,
    /// then pointer-based I420 conversion. The surface must already be
    /// locked read-only by the caller.
    private func downscaleAndConvert(_ surface: IOSurface) -> Data? {
        downscaleAndConvert(surface, converter: converter, scaledPixels: &scaledPixels, scaleTemp: &scaleTemp)
    }

    private func downscaleAndConvert(
        _ surface: IOSurface, converter: BGRAToI420Converter,
        scaledPixels: inout Data, scaleTemp: inout Data
    ) -> Data? {
        let srcW = IOSurfaceGetWidth(surface)
        let srcH = IOSurfaceGetHeight(surface)
        let dstW = max(2, srcW / scale) & ~1
        let dstH = max(2, srcH / scale) & ~1
        let dstRowBytes = dstW * 4
        if scaledPixels.count != dstRowBytes * dstH {
            scaledPixels = Data(count: dstRowBytes * dstH)
        }
        var src = vImage_Buffer(
            data: IOSurfaceGetBaseAddress(surface),
            height: vImagePixelCount(srcH),
            width: vImagePixelCount(srcW),
            rowBytes: IOSurfaceGetBytesPerRow(surface)
        )
        return scaledPixels.withUnsafeMutableBytes { raw -> Data? in
            var dst = vImage_Buffer(
                data: raw.baseAddress,
                height: vImagePixelCount(dstH),
                width: vImagePixelCount(dstW),
                rowBytes: dstRowBytes
            )
            let tempSize = vImageScale_ARGB8888(
                &src, &dst, nil, vImage_Flags(kvImageGetTempBufferSize)
            )
            if tempSize > 0, scaleTemp.count < tempSize {
                scaleTemp = Data(count: tempSize)
            }
            let error = scaleTemp.withUnsafeMutableBytes { temp in
                vImageScale_ARGB8888(&src, &dst, temp.baseAddress, vImage_Flags(kvImageNoFlags))
            }
            guard error == kvImageNoError else { return nil }
            return converter.convert(
                base: raw.baseAddress!,
                rowBytes: dstRowBytes,
                width: dstW,
                height: dstH
            )
        }
    }

    /// Emits the cached planes without conversion (used for both fresh
    /// frames right after conversion and idle pump re-emits).
    private func emitCached() {
        guard let onFrame else { return }
        let micros = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        payloadCache.withPayload(captureMicros: micros) { payload in
            onFrame(payload)
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
            leeway: .milliseconds(2)
        )
        timer.setEventHandler { [weak self] in self?.emitCached() }
        timer.resume()
        pump = timer
    }

    private func readBigEndianU32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: offset ..< (offset + 4))
        }
        return UInt32(bigEndian: value)
    }
}

/// The replayable part of raw capture. Pixel updates and SimulatorKit
/// property updates are independent, so an idle replay always combines the
/// last converted planes with the newest orientation.
struct RawFramePayloadCache {
    private var planes = Data()
    private var width = 0
    private var height = 0
    private var uiOrientationRaw: UInt32 = 0
    private var canvas: DisplayCanvas?
    private var presenting: DisplayPanel?
    /// Whole degrees. A sweep is dozens of samples a second; the layout
    /// is restated only when the rounded angle moves.
    private var hingeDegrees: Double?

    /// A foldable's layout, stated once and whenever its presenting panel
    /// moves.
    mutating func update(canvas: DisplayCanvas, presenting: DisplayPanel?) {
        guard canvas != self.canvas || presenting != self.presenting else { return }
        self.canvas = canvas
        self.presenting = presenting
        restateLayout()
    }

    /// Records the hinge. Returns whether the layout changed, so a sample
    /// that rounds to the angle already stated does not emit a frame.
    mutating func update(hingeDegrees degrees: Double) -> Bool {
        let quantized = degrees.rounded()
        guard hingeDegrees != quantized else { return false }
        hingeDegrees = quantized
        restateLayout()
        return true
    }

    /// `uiOrientationRaw` is already in the phone convention for the
    /// presenting panel; its own mirroring is its own inverse, which gives
    /// back the value every panel restates for itself.
    private(set) var layoutJSON: String?

    /// Serialised when something it states has moved, not per frame.
    private mutating func restateLayout() {
        layoutJSON = canvas.map {
            $0.layoutJSON(
                activeScreenID: presenting?.screenID,
                uiOrientationRaw: presenting?.canonicalUIOrientation(Int(uiOrientationRaw)) ?? Int(uiOrientationRaw),
                hingeDegrees: hingeDegrees
            )
        }
    }

    mutating func store(width: Int, height: Int, planes: Data) {
        self.width = width
        self.height = height
        self.planes = planes
    }

    mutating func update(metadata: ScreenMetadata) {
        let raw = metadata.uiOrientation?.rawValue ?? 0
        guard raw != uiOrientationRaw else { return }
        uiOrientationRaw = raw
        restateLayout()
    }

    mutating func clear() {
        planes = Data()
        width = 0
        height = 0
        uiOrientationRaw = 0
        canvas = nil
        presenting = nil
        hingeDegrees = nil
        layoutJSON = nil
    }

    func withPayload(
        captureMicros: UInt64,
        _ body: (RawFrameCapture.Payload) -> Void
    ) {
        guard !planes.isEmpty else { return }
        let layoutJSON = layoutJSON
        planes.withUnsafeBytes { raw in
            body(RawFrameCapture.Payload(
                width: width,
                height: height,
                captureMicros: captureMicros,
                uiOrientationRaw: uiOrientationRaw,
                planes: raw,
                layoutJSON: layoutJSON
            ))
        }
    }
}
