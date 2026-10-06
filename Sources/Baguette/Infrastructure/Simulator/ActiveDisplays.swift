import Foundation

/// Which panel each foldable simulator is presenting on, shared by
/// everything that has to follow it: the screen picks that panel's
/// framebuffer, input addresses its digitizer, accessibility scales to
/// its size.
///
/// Core Device is the authority. Nothing in-process says which panel is
/// live — both framebuffer ports stay powered and keep a surface — and
/// the hinge angle only suggests it: SpringBoard's pose provider has
/// hysteresis, and an app may light the cover panel while the device is
/// open (iOS 27.1's camera capture scene accessory), so `≥ 90°` is not
/// "the inner panel is lit". The answer comes from `devicectl device
/// info displays` (~0.5 s), far too slow to ask per frame or per touch.
///
/// While a `Screen` is watching, the hinge says *when* to ask: its
/// monitor (`SharedHinge`, one per device, change-driven) delivers every
/// sample of a sweep, and once the samples stop the device is asked a
/// few times over the next seconds (`settleDelays`) — not during the
/// sweep, when a read competes with the fold itself, and not just once,
/// because SpringBoard swaps panels on its own schedule after the pose
/// settles. Every sample re-arms the whole series, so a sweep of any
/// length costs at most that many reads, on one serial queue so they
/// never overlap. A slow poll catches what no hinge motion announces.
/// With nobody watching — a one-shot CLI gesture — the last answer
/// stands for a couple of seconds and is asked for again on demand.
///
/// A single-display device never gets here: `panels(of:)` is one
/// in-process read and the callers keep their existing path.
final class ActiveDisplays: @unchecked Sendable {
    static let shared = ActiveDisplays()

    private struct Entry {
        var screenID: UInt32?
        var readAt: Date
    }

    private struct Watch {
        let hinge: any HingeWatch
        let poll: DispatchSourceTimer
        var settles: [DispatchWorkItem] = []
    }

    /// How long an unwatched answer stands before it is asked for again.
    static let unwatchedLifetime: TimeInterval = 2
    /// The fallback cadence while watched: a panel that changes without
    /// the hinge moving is followed within this.
    static let pollInterval: TimeInterval = 5
    /// When the device is asked after the hinge's last sample. The first
    /// outlasts a gap in Device Hub's 60 Hz sweep and lands after a prompt
    /// swap; the later two catch the pose provider taking its time (its
    /// hysteresis, an app releasing the cover), so a fold is followed
    /// within a few seconds however SpringBoard schedules the swap.
    static let settleDelays: [TimeInterval] = [0.3, 1.0, 3.0]

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var watches: [String: Watch] = [:]
    private var listeners: [String: [ObjectIdentifier: @Sendable () -> Void]] = [:]
    private let queue = DispatchQueue(label: "baguette.active-displays", qos: .utility)
    private let hinge: (String) -> any Hinge
    private let ask: (String) -> UInt32?
    private let settleDelays: [TimeInterval]

    /// `hinge` is the monitor whose samples trigger a read; `ask` is the
    /// read itself (Core Device in production). Both injectable, as are
    /// the delays, so the bookkeeping is unit-covered without a device.
    init(
        hinge: @escaping (String) -> any Hinge = { udid in
            SharedHinge.forDevice(udid, make: { DevicectlHinge(udid: udid) })
        },
        ask: @escaping (String) -> UInt32? = ActiveDisplays.askCoreDevice,
        settleDelays: [TimeInterval] = ActiveDisplays.settleDelays
    ) {
        self.hinge = hinge
        self.ask = ask
        self.settleDelays = settleDelays
    }

    /// The integrated panels of a device's type. Cheap and in-process.
    static func panels(of device: NSObject?) -> DisplayPanels {
        let deviceType = device?.value(forKey: "deviceType") as? NSObject
        return DisplayPanels.parsing(deviceType?.value(forKey: "capabilities") as? [String: Any])
    }

    /// The panel a foldable is presenting on; nil for a single-display
    /// device, or when Core Device cannot say (callers fall back to the
    /// main panel's existing path).
    func activePanel(udid: String, device: NSObject?) -> DisplayPanel? {
        activePanel(udid: udid, among: Self.panels(of: device))
    }

    /// The presenting panel by its Connected Screens name — what the
    /// chrome, the 3D book and the phone plane's bind go by. Nil on a
    /// single-display device or when Core Device cannot say.
    func litPanel(udid: String, device: NSObject?) -> IntegratedPanel? {
        let panels = Self.panels(of: device)
        guard let active = activePanel(udid: udid, among: panels) else { return nil }
        return panels.integratedPanel(active)
    }

    /// Same, for a caller that already holds the device's panels — a
    /// `Screen` asks once per frame and must not re-parse them.
    func activePanel(udid: String, among panels: DisplayPanels) -> DisplayPanel? {
        guard panels.isFoldable else { return nil }
        lock.lock()
        let entry = entries[udid]
        let watched = watches[udid] != nil
        lock.unlock()
        // Watched: the reads keep it current; never block a frame on one.
        if watched, let entry { return entry.screenID.flatMap(panels.panel(screenID:)) }
        let age = entry.map { Date().timeIntervalSince($0.readAt) } ?? .infinity
        let screenID = age < Self.unwatchedLifetime ? entry?.screenID : read(udid: udid).screenID
        return screenID.flatMap(panels.panel(screenID:))
    }

    /// Follows the device for as long as anyone watches it. `onChange`
    /// runs when the presenting panel is first known and whenever it
    /// moves.
    func beginWatching(udid: String, owner: AnyObject, onChange: @escaping @Sendable () -> Void) {
        lock.lock()
        listeners[udid, default: [:]][ObjectIdentifier(owner)] = onChange
        let start = watches[udid] == nil
        lock.unlock()
        guard start else { return }

        let poll = DispatchSource.makeTimerSource(queue: queue)
        poll.schedule(deadline: .now(), repeating: Self.pollInterval, leeway: .milliseconds(250))
        poll.setEventHandler { [weak self] in self?.poll(udid: udid) }
        let hinge = self.hinge(udid).watch { [weak self] _ in
            self?.hingeMoved(udid: udid)
        }
        lock.lock()
        if watches[udid] == nil {
            watches[udid] = Watch(hinge: hinge, poll: poll)
            lock.unlock()
            poll.resume()
        } else {
            // Two callers starting at once: the second set is redundant.
            lock.unlock()
            hinge.cancel()
            poll.cancel()
        }
    }

    func endWatching(udid: String, owner: AnyObject) {
        lock.lock()
        listeners[udid]?[ObjectIdentifier(owner)] = nil
        let stop = (listeners[udid]?.isEmpty ?? true) ? watches.removeValue(forKey: udid) : nil
        lock.unlock()
        guard let stop else { return }
        stop.hinge.cancel()
        stop.poll.cancel()
        stop.settles.forEach { $0.cancel() }
    }

    /// A hinge sample: the fold is in progress. Ask at each settle delay
    /// after it, re-arming the series on every sample so one sweep costs
    /// at most `settleDelays.count` reads.
    private func hingeMoved(udid: String) {
        let series = settleDelays.map { _ in
            DispatchWorkItem { [weak self] in self?.poll(udid: udid) }
        }
        lock.lock()
        guard var watch = watches[udid] else {
            lock.unlock()
            return
        }
        watch.settles.forEach { $0.cancel() }
        watch.settles = series
        watches[udid] = watch
        lock.unlock()
        for (delay, work) in zip(settleDelays, series) {
            queue.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func poll(udid: String) {
        guard read(udid: udid).moved else { return }
        lock.lock()
        let hearing = listeners[udid].map { Array($0.values) } ?? []
        lock.unlock()
        hearing.forEach { $0() }
    }

    /// Asks Core Device. A failure to answer (mid-swap, a busy host) is not
    /// news: the last panel it named stands. `moved` is true when the
    /// presenting panel is first known or differs from the last answer.
    @discardableResult
    private func read(udid: String) -> (screenID: UInt32?, moved: Bool) {
        let answer = ask(udid)
        lock.lock()
        defer { lock.unlock() }
        let last = entries[udid]?.screenID
        guard let answer else {
            if entries[udid] == nil { entries[udid] = Entry(screenID: nil, readAt: Date()) }
            return (last, false)
        }
        entries[udid] = Entry(screenID: answer, readAt: Date())
        return (answer, answer != last)
    }

    /// The irreducible call: one `devicectl` run, its JSON on stdout.
    static func askCoreDevice(udid: String) -> UInt32? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "devicectl", "device", "info", "displays", "--device", udid,
            "--quiet", "--json-output", "-", "--timeout", "10",
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ActiveDisplayReport.activeScreenID(in: data)
    }
}
