import Foundation

/// Puts what another process draws inside the frontmost app where it is on
/// screen.
///
/// A share sheet, a document picker, a keyboard extension: the app shows
/// them, another process draws them, and that process reports its
/// elements' frames from its own view's corner, not the screen's. A share
/// sheet standing at y 480 says its first button is at y 77, and a tap on
/// the frame's centre lands in the page above it.
///
/// Nothing in the tree says where such a view stands. The sweep does: each
/// element it found, it found by hit-testing a screen point, so that point
/// is inside the element. Every hit on one process bounds the one shift
/// its frames need, the shift most of them agree on is a run a grid step
/// wide at most, and a few more hit-tests between two neighbouring elements
/// find where one gives way to the other, which says the rest. The walk reaches the same elements through the
/// app, so the shift is applied to the whole tree. The app's own process
/// and SpringBoard's status bar are never moved. A process whose frames already hold their points — the
/// app's own, the status bar's — is left alone.
enum AXRemoteFrames {
    struct Hit: Equatable {
        var point: Point
        var node: AXNode
    }

    /// How far one process's frames are from the screen.
    struct Shift: Equatable {
        var x: Double
        var y: Double
    }

    /// The shift each displaced process needs, by process. `probe`
    /// hit-tests one more point; it is asked only for a process that needs
    /// placing, and not at all once `keepGoing` says the sweep is out of
    /// time.
    /// `app` is the process of the tree's root, whose frames are the
    /// screen's by definition, and `statusStrip` the band SpringBoard's
    /// status bar occupies: a process seen only there is SpringBoard, and
    /// its frames are the screen's too.
    static func shifts(
        _ hits: [Hit],
        app: String? = nil,
        statusStrip: Rect? = nil,
        keepGoing: () -> Bool = { true },
        probe: (Point) -> AXNode? = { _ in nil }
    ) -> [String: Shift] {
        var shifts: [String: Shift] = [:]
        for (process, own) in Dictionary(grouping: hits, by: { $0.node.process ?? "" }) where !process.isEmpty {
            if process == app { continue }
            if let statusStrip, own.allSatisfy({ statusStrip.holds($0.point) }) { continue }
            guard let shift = shift(for: own, keepGoing: keepGoing, probe: probe) else { continue }
            shifts[process] = Shift(x: shift.x, y: shift.y)
        }
        return shifts
    }

    /// The widest run of shifts worth acting on: wider, and the hits say too
    /// little about where the view stands.
    private static let widestRun = 64.0
    private static let slack = 0.5

    private static func shift(
        for hits: [Hit], keepGoing: () -> Bool, probe: (Point) -> AXNode?
    ) -> (x: Double, y: Double)? {
        let sized = hits.filter { $0.node.frame.size.width > 0 && $0.node.frame.size.height > 0 }
        // A shift `s` suits a hit when its point lies in its frame moved by
        // `s`: point − frame.max ≤ s ≤ point − frame.min. Not every hit is
        // inside its element — a point in a container's padding answers
        // with the nearest element — so the shift is the one most hits
        // agree on, not the one all of them allow.
        guard
            let x = agreed(sized.map { ($0.point.x - $0.node.frame.origin.x - $0.node.frame.size.width, $0.point.x - $0.node.frame.origin.x) }),
            let y = agreed(sized.map { ($0.point.y - $0.node.frame.origin.y - $0.node.frame.size.height, $0.point.y - $0.node.frame.origin.y) })
        else { return nil }
        // Already where they say they are: no shift suits more hits than
        // none at all does, on either axis.
        if x.zeroSuits, y.zeroSuits { return nil }
        guard x.high - x.low <= widestRun, y.high - y.low <= widestRun else { return nil }

        // The hits bound each axis to a run a grid step wide. Where one
        // element ends and its neighbour begins is found on screen exactly,
        // and says the rest; an element's outer edge would not, because a
        // point just outside it still answers with it.
        let shiftY = boundary(
            in: sized, low: y.low, high: y.high, acrossShift: (x.low + x.high) / 2,
            keepGoing: keepGoing, probe: probe,
            along: { $0.y }, across: { $0.x }, start: { $0.origin.y }, length: { $0.size.height },
            crossStart: { $0.origin.x }, crossLength: { $0.size.width },
            point: { Point(x: $1, y: $0) }) ?? (y.low + y.high) / 2
        let shiftX = boundary(
            in: sized, low: x.low, high: x.high, acrossShift: shiftY,
            keepGoing: keepGoing, probe: probe,
            along: { $0.x }, across: { $0.y }, start: { $0.origin.x }, length: { $0.size.width },
            crossStart: { $0.origin.y }, crossLength: { $0.size.height },
            point: { Point(x: $0, y: $1) }) ?? (x.low + x.high) / 2
        return (shiftX.rounded(), shiftY.rounded())
    }

    /// The shift along one axis that the meeting of two neighbouring
    /// elements gives: two hits on one grid line, on elements whose frames
    /// meet (or nearly) along the axis, and between the two points the
    /// place on screen where the answer changes from one to the other.
    /// Nil when no such pair was hit or time runs out.
    private static func boundary(
        in hits: [Hit], low: Double, high: Double, acrossShift: Double,
        keepGoing: () -> Bool, probe: (Point) -> AXNode?,
        along: (Point) -> Double, across: (Point) -> Double,
        start: (Rect) -> Double, length: (Rect) -> Double,
        crossStart: (Rect) -> Double, crossLength: (Rect) -> Double,
        point: (Double, Double) -> Point
    ) -> Double? {
        let widestGap = 8.0
        // Each pair of elements is tried once, and only a few pairs: a
        // search is half a dozen hit-tests.
        var tried = Set<String>()
        for first in hits {
            guard let firstID = first.node.nodeId else { continue }
            let end = start(first.node.frame) + length(first.node.frame)
            for second in hits where second.node.nodeId != nil && second.node.nodeId != firstID {
                guard tried.count < 6 else { return nil }
                let gap = start(second.node.frame) - end
                // On one grid line, the second element starting where the
                // first ends, and that line inside both across the axis.
                guard across(first.point) == across(second.point), along(first.point) < along(second.point),
                    gap >= -1, gap <= widestGap
                else { continue }
                let line = across(first.point)
                // The line crosses both, by the shift across the axis as
                // far as it is known.
                func inside(_ frame: Rect) -> Bool {
                    let local = line - acrossShift
                    return local >= crossStart(frame) - 16 && local <= crossStart(frame) + crossLength(frame) + 16
                }
                guard inside(first.node.frame), inside(second.node.frame),
                    tried.insert("\(firstID)|\(second.node.nodeId ?? "")").inserted
                else { continue }
                var before = along(first.point)
                var after = along(second.point)
                while after - before > 0.5 {
                    guard keepGoing() else { return nil }
                    let middle = (before + after) / 2
                    let answer = probe(point(middle, line))?.nodeId
                    if answer == firstID {
                        before = middle
                    } else if answer == second.node.nodeId {
                        after = middle
                    } else {
                        // Something else lies between them here.
                        break
                    }
                }
                guard after - before <= 0.5 else { continue }
                let shift = (before + after) / 2 - (end + gap / 2)
                // Near what the hits allow, not within it: the run leans
                // outward, because a point just outside an element still
                // answers with it.
                guard shift >= low - 16, shift <= high + 16 else { continue }
                return shift
            }
        }
        return nil
    }

    /// The run of values the most intervals share, and whether zero suits
    /// about as many; nil when fewer than three intervals, or fewer than
    /// half of them, agree on anything.
    private static func agreed(_ intervals: [(Double, Double)]) -> (low: Double, high: Double, zeroSuits: Bool)? {
        guard intervals.count >= 3 else { return nil }
        func count(at value: Double) -> Int {
            intervals.filter { $0.0 - slack <= value && value <= $0.1 + slack }.count
        }
        // The best run starts at some interval's start.
        var best = (count: 0, low: 0.0)
        for start in intervals.map(\.0) {
            let here = count(at: start)
            if here > best.count { best = (here, start) }
        }
        guard best.count >= 3, best.count * 2 >= intervals.count else { return nil }
        // It ends at the nearest end among the intervals that hold it.
        let high = intervals.filter { $0.0 - slack <= best.low && best.low <= $0.1 + slack }.map(\.1).min() ?? best.low
        // A stray hit or two (a point in padding answers with the nearest
        // element) can put some other shift ahead of zero by as many.
        let margin = max(2, intervals.count / 20)
        return (best.low, high, count(at: 0) + margin >= best.count)
    }
}

extension AXNode {
    /// The process an element belongs to, as its node identity names it
    /// (`ax1:<device>:<pid>:<start>:<object>`); nil without one.
    var process: String? {
        guard let parts = nodeId?.split(separator: ":"), parts.count == 5 else { return nil }
        return "\(parts[2]):\(parts[3])"
    }

    /// This tree with every element of a displaced process moved onto
    /// the screen: the walk reaches such elements too, through the app
    /// that hosts their view, with the same frames.
    func placed(by shifts: [String: AXRemoteFrames.Shift]) -> AXNode {
        guard !shifts.isEmpty else { return self }
        let shift = process.flatMap { shifts[$0] }
        func moved(_ point: Point) -> Point {
            guard let shift else { return point }
            return Point(x: point.x + shift.x, y: point.y + shift.y)
        }
        return AXNode(
            role: role, subrole: subrole, label: label, value: value,
            identifier: identifier, nodeId: nodeId, title: title, help: help,
            frame: Rect(origin: moved(frame.origin), size: frame.size),
            activationPoint: activationPoint.map(moved),
            sliderTrack: sliderTrack?.map(moved),
            adjustmentActions: adjustmentActions,
            enabled: enabled, focused: focused, hidden: hidden,
            children: children.map { $0.placed(by: shifts) },
            screen: screen
        )
    }
}

extension Rect {
    fileprivate func holds(_ point: Point) -> Bool {
        point.x >= origin.x && point.x <= origin.x + size.width
            && point.y >= origin.y && point.y <= origin.y + size.height
    }
}
