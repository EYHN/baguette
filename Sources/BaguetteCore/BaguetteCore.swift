import Foundation

public struct BaguetteCoreHarness: Sendable {
    public let deviceSetPath: String?

    public init(deviceSetPath: String? = nil) {
        self.deviceSetPath = deviceSetPath
    }

    public var listJSON: String {
        simulators.listJSON
    }

    public func boot(udid: String) throws {
        try simulator(udid: udid).boot()
    }

    public func shutdown(udid: String) throws {
        try simulator(udid: udid).shutdown()
    }

    public func create(name: String, model: String, runtime: String) throws -> String {
        try runAndCapture("/usr/bin/xcrun", ["simctl", "create", name, model, runtime])
    }

    public func delete(udid: String) throws {
        _ = try runAndCapture("/usr/bin/xcrun", ["simctl", "delete", udid])
    }

    public func screenshot(udid: String, quality: Double = 0.85, scale: Int = 1) async throws -> Data {
        try await ScreenSnapshot.capture(
            screen: simulator(udid: udid).screen(),
            quality: quality,
            scale: max(1, scale)
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

    public func dispatchInputLine(udid: String, line: String) throws -> String {
        let input = try simulator(udid: udid).input()
        return GestureDispatcher(input: input).dispatch(line: line)
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

    public func runServer(host: String = "127.0.0.1", port: Int = 8421) async throws {
        let server = Server(
            simulators: simulators,
            chromes: Self.defaultChromes(),
            host: host,
            port: port
        )
        try await server.run()
    }

    private var simulators: CoreSimulators {
        CoreSimulators(deviceSetPath: deviceSetPath)
    }

    private func simulator(udid: String) throws -> any Simulator {
        guard let simulator = simulators.find(udid: udid) else {
            throw BaguetteCoreError.notFound("Device \(udid) not found")
        }
        return simulator
    }

    private static func defaultChromes() -> any Chromes {
        LiveChromes(
            store: FileSystemChromeStore(),
            rasterizer: CoreGraphicsPDFRasterizer()
        )
    }
}

/// Persistent input dispatcher for one simulator (see `makeInputSession`).
public final class InputSession: @unchecked Sendable {
    private let lock = NSLock()
    private let dispatcher: GestureDispatcher

    init(input: any Input) {
        self.dispatcher = GestureDispatcher(input: input)
    }

    /// Dispatches one JSON gesture line and returns a one-line JSON ack.
    public func dispatch(line: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return dispatcher.dispatch(line: line)
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
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        throw BaguetteCoreError.processFailed(err.isEmpty ? out : err)
    }
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
}
