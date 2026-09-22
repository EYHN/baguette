import Foundation

public struct BaguetteCoreHarness: Sendable {
    public let deviceSetPath: String?

    public init(deviceSetPath: String? = nil) {
        self.deviceSetPath = deviceSetPath
    }

    public var listJSON: String {
        simulators.listJSON
    }

    public func runtimeProfilesJSON() throws -> String {
        try runSimctl(["list", "-j", "runtimes"])
    }

    public func boot(udid: String) throws {
        try simulator(udid: udid).boot()
    }

    public func shutdown(udid: String) throws {
        try simulator(udid: udid).shutdown()
    }

    /// Whether Xcode 27's Device Hub has attached to this device and so
    /// shadows the legacy input surface (see `InputSurface`): what is lost
    /// varies by runtime — buttons alone on iOS 26, more on iOS 27 — and
    /// `heal` is the one repair for all of it. False for a device that is
    /// shut down or a host without Device Hub.
    public func inputSurfaceShadowed(udid: String) async throws -> Bool {
        await SimctlInputSurface().shadowed(on: try simulator(udid: udid))
    }

    /// The major version of the device's runtime; nil when unreadable.
    public func runtimeMajor(udid: String) -> Int? {
        ScreenOrientation.runtimeMajor(of: simulators.resolveDevice(udid: udid))
    }

    /// Reclaims the input surface if Device Hub shadowed it; returns
    /// whether a reclaim ran. Reclaiming restarts backboardd, so running
    /// apps are killed. `afterBoot` first waits for the fresh guest (and
    /// Device Hub's attach) to settle, as `baguette boot` does.
    public func healInputSurface(udid: String, afterBoot: Bool) async throws -> Bool {
        let simulator = try simulator(udid: udid)
        let surface = SimctlInputSurface()
        let outcome = afterBoot
            ? try await surface.healAfterBoot(on: simulator)
            : try await surface.heal(on: simulator)
        return outcome == .reclaimed
    }

    public func create(name: String, model: String, runtime: String) throws -> String {
        try runSimctl(["create", name, model, runtime])
    }

    public func delete(udid: String) throws {
        _ = try runSimctl(["delete", udid])
    }

    public func screenshot(udid: String, quality: Double = 0.85, scale: Int = 1) async throws -> Data {
        try await ScreenSnapshot.capture(
            screen: simulator(udid: udid).screen(),
            quality: quality,
            scale: max(1, scale)
        )
    }

    /// The device on its 3D model, for an agent to look at: a phone as it
    /// stands, a foldable with the hinge at its actual angle and the panel
    /// it is presenting on lit. The scene stays warm per device, so a shot
    /// every few seconds costs a paint and a render, not a model load.
    ///
    /// `rotation` turns the model (X, Y, Z degrees); `size` is the canvas in
    /// pixels; `background` is `transparent` or `#RRGGBB`. `fallbackModelRoots`
    /// are searched after baguette's own model roots — an embedding host
    /// that carries the model catalog itself (no sidecar bundle next to
    /// its executable) hands its unpacked copy in here. The RealityKit
    /// stage is main-actor bound: the process's main dispatch queue must be
    /// serviced (a hosting app's run loop, or `dispatch_main`).
    public func screenshot3D(
        udid: String,
        rotation: (x: Double, y: Double, z: Double) = (0, 0, 0),
        size: (width: Int, height: Int) = (1024, 1024),
        background: String = "transparent",
        fallbackModelRoots: [URL] = []
    ) async throws -> Screenshot3D {
        let simulator = try simulator(udid: udid)
        let models = try LiveDeviceModels(rootURLs: DeviceModelRoots.standard() + fallbackModelRoots)
        guard let model = try simulator.deviceModel(in: models) else {
            throw BaguetteCoreError.notFound("no 3D model covers \(simulator.deviceTypeName)")
        }
        guard size.width > 0, size.height > 0 else {
            throw BaguetteCoreError.invalidArgument("size must be positive")
        }
        let canvas: DeviceRenderBackground
        if background == "transparent" {
            canvas = .transparent
        } else if background.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil {
            canvas = .color(background)
        } else {
            throw BaguetteCoreError.invalidArgument("background must be transparent or #RRGGBB")
        }
        var request = Device3DSnapshotRequest.standard
        request.rotation = DeviceRotation(x: rotation.x, y: rotation.y, z: rotation.z)
        request.outputSize = RenderDimensions(width: size.width, height: size.height)
        request.background = canvas
        let snapshot = try await Device3DSnapshots.shared.snapshot(
            udid: udid, model: model, request: request,
            source: .live(simulator: simulator)
        )
        return Screenshot3D(
            png: snapshot.png,
            foldable: snapshot.foldable,
            hingeDegrees: snapshot.hingeDegrees,
            litPanel: snapshot.litPanel.map { $0 == .primary ? "primary" : "secondary" }
        )
    }

    /// A foldable's hinge and lit panel right now; nil for a device that
    /// does not fold. `hingeDegrees` is nil when no reading has arrived,
    /// `litPanel` when Core Device could not say.
    public func foldableState(udid: String) throws -> FoldableState? {
        let simulator = try simulator(udid: udid)
        guard ActiveDisplays.panels(of: simulators.resolveDevice(udid: udid)).isFoldable else { return nil }
        return FoldableState(
            hingeDegrees: simulator.hinge().angle()?.degrees,
            litPanel: simulator.litPanel().map { $0 == .primary ? "primary" : "secondary" }
        )
    }

    public func describeUI(udid: String, x: Double? = nil, y: Double? = nil) throws -> String {
        let ax = try simulator(udid: udid).accessibility()
        let result: AXNode?
        switch (x, y) {
        case let (px?, py?):
            result = try ax.describeAt(point: Point(x: px, y: py))
        case (nil, nil):
            result = try ax.describeAll()
        default:
            throw BaguetteCoreError.invalidArgument("--x and --y must be supplied together")
        }
        guard let result else {
            throw BaguetteCoreError.noAccessibilityData
        }
        return result.json
    }

    public func chromeLayout(udid: String) throws -> String {
        let chromes = Self.defaultChromes()
        guard let json = try simulator(udid: udid).chrome(in: chromes)?.layoutJSON() else {
            throw BaguetteCoreError.notFound("no chrome bundle covers \(udid)")
        }
        return json
    }

    public func adjustUI(udid: String, request: String) throws -> String {
        guard let ax = try simulator(udid: udid).accessibility() as? AXPTranslatorAccessibility else {
            throw BaguetteCoreError.invalidArgument("semantic adjustment unavailable")
        }
        return try ax.adjust(request: request)
    }

    public func devicePresentation(udid: String) throws -> DevicePresentationSnapshot {
        let simulator = try simulator(udid: udid)
        let presentation = try Self.presentations
            .presentation(forDeviceName: simulator.deviceTypeName)
        // A foldable is described by whichever panel it is presenting on.
        let device = simulators.resolveDevice(udid: udid)
        let panels = ActiveDisplays.panels(of: device)
        guard let panel = ActiveDisplays.shared.activePanel(udid: udid, among: panels) else {
            return presentation.snapshot
        }
        return presentation.presenting(on: panel, of: panels).snapshot
    }

    public func dispatchInputLine(udid: String, line: String) throws -> String {
        let input = try simulator(udid: udid).input()
        return DisplayAddress.dispatch(line, to: input, through: GestureDispatcher(input: input))
    }

    /// A persistent input dispatcher for one simulator. Reuses the warmed-up
    /// HID connection across events, so high-rate gesture streams don't pay
    /// per-event setup cost. Safe to call from any thread; dispatch is
    /// serialized internally.
    public func makeInputSession(udid: String) throws -> InputSession {
        InputSession(input: try simulator(udid: udid).input())
    }

    /// Starts a live unified-log feed and returns a handle that stops it.
    /// `onLine` fires once per log line, `onTerminate` once when the feed
    /// ends (nil on clean stop).
    public func startLogStream(
        udid: String,
        level: String = "info",
        style: String = "default",
        predicate: String? = nil,
        bundleId: String? = nil,
        onLine: @escaping @Sendable (String) -> Void,
        onTerminate: @escaping @Sendable (String?) -> Void
    ) throws -> LogSession {
        guard let lvl = LogFilter.Level(wire: level) else {
            throw BaguetteCoreError.invalidArgument("invalid log level: \(level)")
        }
        guard let sty = LogFilter.Style(wire: style) else {
            throw BaguetteCoreError.invalidArgument("invalid log style: \(style)")
        }
        let stream = try simulator(udid: udid).logs()
        try stream.start(
            filter: LogFilter(level: lvl, style: sty, predicate: predicate, bundleId: bundleId),
            onLine: onLine,
            onTerminate: { error in
                onTerminate(error.map { "\($0)" })
            }
        )
        return LogSession(stream: stream)
    }

    public func streamLogs(
        udid: String,
        level: String = "info",
        style: String = "default",
        predicate: String? = nil,
        bundleId: String? = nil,
        maxLines: Int? = nil,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws {
        guard let lvl = LogFilter.Level(wire: level) else {
            throw BaguetteCoreError.invalidArgument("invalid log level: \(level)")
        }
        guard let sty = LogFilter.Style(wire: style) else {
            throw BaguetteCoreError.invalidArgument("invalid log style: \(style)")
        }
        let stream = try simulator(udid: udid).logs()
        let done = Once()
        let counter = LockedCounter(limit: maxLines)
        try stream.start(
            filter: LogFilter(level: lvl, style: sty, predicate: predicate, bundleId: bundleId),
            onLine: { line in
                onLine(line)
                if counter.tick() {
                    stream.stop()
                    done.fire()
                }
            },
            onTerminate: { _ in
                done.fire()
            }
        )
        await done.wait()
        stream.stop()
    }

    var simulators: CoreSimulators {
        CoreSimulators(deviceSetPath: deviceSetPath)
    }

    private func simulator(udid: String) throws -> any Simulator {
        guard let simulator = simulators.find(udid: udid) else {
            throw BaguetteCoreError.notFound("Device \(udid) not found")
        }
        return simulator
    }

    private func runSimctl(_ arguments: [String]) throws -> String {
        var command = ["simctl"]
        if let deviceSetPath {
            command += ["--set", deviceSetPath]
        }
        command += arguments
        return try runAndCapture("/usr/bin/xcrun", command)
    }

    static func defaultChromes() -> any Chromes {
        LiveChromes(
            store: FileSystemChromeStore(),
            rasterizer: CoreGraphicsPDFRasterizer()
        )
    }

    private static let presentations = LiveDevicePresentations(
        store: FileSystemChromeStore(),
        rasterizer: CoreGraphicsPDFRasterizer()
    )
}

/// One `screenshot3D`: the PNG and what the device was doing in it.
public struct Screenshot3D: Sendable {
    public let png: Data
    /// Whether the model folds — the two fields below mean something.
    public let foldable: Bool
    /// The hinge's angle as posed; nil on a phone or with no reading.
    public let hingeDegrees: Double?
    /// `"primary"` (cover) or `"secondary"` (unfolded); nil on a phone.
    public let litPanel: String?
}

/// A foldable's hinge and lit panel (see `foldableState`).
public struct FoldableState: Sendable, Equatable {
    public let hingeDegrees: Double?
    public let litPanel: String?

    public var json: String {
        let degrees = hingeDegrees.map { "\($0)" } ?? "null"
        let panel = litPanel.map { "\"\($0)\"" } ?? "null"
        return #"{"foldable":true,"hingeDegrees":\#(degrees),"litPanel":\#(panel)}"#
    }
}

/// Persistent input dispatcher for one simulator (see `makeInputSession`).
public final class InputSession: @unchecked Sendable {
    private let lock = NSLock()
    private let input: any Input
    private let dispatcher: GestureDispatcher

    init(input: any Input) {
        self.input = input
        self.dispatcher = GestureDispatcher(input: input)
    }

    /// Dispatches one JSON gesture line and returns a one-line JSON ack.
    public func dispatch(line: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return DisplayAddress.dispatch(line, to: input, through: dispatcher)
    }
}

/// Handle for a running log feed (see `startLogStream`). Stop is idempotent;
/// dropping the handle without stopping leaves the feed running.
public final class LogSession: Sendable {
    private let stream: any LogStream

    init(stream: any LogStream) {
        self.stream = stream
    }

    public func stop() {
        stream.stop()
    }
}

public enum BaguetteCoreError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case noAccessibilityData
    case notFound(String)
    case processFailed(String)

    public var description: String {
        switch self {
        case .invalidArgument(let message):
            message
        case .noAccessibilityData:
            "no accessibility data"
        case .notFound(let message):
            message
        case .processFailed(let message):
            message
        }
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if fired {
                lock.unlock()
                continuation.resume()
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func fire() {
        lock.lock()
        guard !fired else {
            lock.unlock()
            return
        }
        fired = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int?
    private var count = 0

    init(limit: Int?) {
        self.limit = limit.map { max(1, $0) }
    }

    func tick() -> Bool {
        guard let limit else { return false }
        lock.lock()
        count += 1
        let reached = count >= limit
        lock.unlock()
        return reached
    }
}

private func runAndCapture(_ executable: String, _ arguments: [String]) throws -> String {
    let result = try HostProcess.capture(
        executable: URL(fileURLWithPath: executable),
        arguments: arguments
    )
    let output = String(data: result.output, encoding: .utf8) ?? ""
    guard result.status == 0 else {
        throw BaguetteCoreError.processFailed(output)
    }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
}
