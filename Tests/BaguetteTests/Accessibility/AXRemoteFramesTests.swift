import Testing
import Foundation
@testable import Baguette

/// A share sheet, a document picker or a keyboard extension is drawn by
/// another process, which reports frames from its own view's corner. The
/// points the sweep found its elements at say where the view stands.
@Suite("Frames of another process's view")
struct AXRemoteFramesTests {
    private static let device = "01234567-89ab-cdef-0123-456789abcdef"
    private static let sheet = "ax1:\(device):700:1700000000-1"
    private static let app = "ax1:\(device):600:1700000000-2"

    private func button(_ process: String, _ object: String, _ x: Double, _ y: Double) -> AXNode {
        AXNode(
            role: "AXButton", label: object, nodeId: "\(process):\(object)",
            frame: Rect(origin: Point(x: x, y: y), size: Size(width: 80, height: 100)))
    }

    /// The hits a 32-point grid makes on `nodes` standing `shift` away from
    /// where their frames say.
    private func hits(on nodes: [AXNode], shiftedBy shift: (x: Double, y: Double)) -> [AXRemoteFrames.Hit] {
        var hits: [AXRemoteFrames.Hit] = []
        for y in stride(from: 16.0, to: 874, by: 32) {
            for x in stride(from: 16.0, to: 402, by: 32) {
                let local = Point(x: x - shift.x, y: y - shift.y)
                if let node = nodes.first(where: { $0.frame.holdsLocal(local) }) {
                    hits.append(AXRemoteFrames.Hit(point: Point(x: x, y: y), node: node))
                }
            }
        }
        return hits
    }

    /// What a hit-test answers at a screen point, for the edge search.
    private func probe(_ nodes: [AXNode], shiftedBy shift: (x: Double, y: Double)) -> (Point) -> AXNode? {
        { point in nodes.first { $0.frame.holdsLocal(Point(x: point.x - shift.x, y: point.y - shift.y)) } }
    }

    @Test func `should find where a displaced view stands from the points that hit it`() {
        // Cells that meet: where one gives way to the next is exact.
        let cells = [button(Self.sheet, "a", 20, 130), button(Self.sheet, "b", 100, 130), button(Self.sheet, "c", 20, 230)]
        let shifts = AXRemoteFrames.shifts(
            hits(on: cells, shiftedBy: (9, 479)), probe: probe(cells, shiftedBy: (9, 479)))

        #expect(shifts == ["700:1700000000-1": AXRemoteFrames.Shift(x: 9, y: 479)])
    }

    @Test func `should come within a grid step when no two elements meet`() throws {
        let cells = [button(Self.sheet, "a", 20, 130), button(Self.sheet, "b", 108, 130), button(Self.sheet, "c", 20, 250)]
        let shift = try #require(AXRemoteFrames.shifts(hits(on: cells, shiftedBy: (0, 479)))["700:1700000000-1"])

        #expect(abs(shift.y - 479) <= 16)
    }

    @Test func `should find a view standing only a little way in`() {
        let cells = [button(Self.sheet, "a", 18, 127), button(Self.sheet, "b", 98, 127), button(Self.sheet, "c", 18, 227)]
        let shifts = AXRemoteFrames.shifts(
            hits(on: cells, shiftedBy: (8, 27)), probe: probe(cells, shiftedBy: (8, 27)))

        #expect(shifts == ["700:1700000000-1": AXRemoteFrames.Shift(x: 8, y: 27)])
    }

    @Test func `should never move the app's own process or the status bar`() {
        let cells = [button(Self.sheet, "a", 20, 130), button(Self.sheet, "b", 108, 130), button(Self.sheet, "c", 20, 250)]
        let found = hits(on: cells, shiftedBy: (9, 479))

        #expect(AXRemoteFrames.shifts(found, app: "700:1700000000-1").isEmpty)
        let everywhere = Rect(origin: Point(x: 0, y: 0), size: Size(width: 402, height: 874))
        #expect(AXRemoteFrames.shifts(found, statusStrip: everywhere).isEmpty)
    }

    @Test func `should leave a process alone whose frames hold the points that hit them`() {
        let own = [button(Self.app, "a", 20, 130), button(Self.app, "b", 108, 130), button(Self.app, "c", 20, 250)]

        #expect(AXRemoteFrames.shifts(hits(on: own, shiftedBy: (0, 0))).isEmpty)
    }

    @Test func `should not move a process on the word of a few stray hits`() {
        // A point in a container's padding answers with the nearest element.
        let own = [button(Self.app, "a", 20, 130), button(Self.app, "b", 108, 130), button(Self.app, "c", 20, 250)]
        var found = hits(on: own, shiftedBy: (0, 0))
        found.append(AXRemoteFrames.Hit(point: Point(x: 16, y: 80), node: own[0]))
        found.append(AXRemoteFrames.Hit(point: Point(x: 240, y: 400), node: own[1]))

        #expect(AXRemoteFrames.shifts(found).isEmpty)
    }

    @Test func `should move every element of the displaced process and no other`() {
        let tree = AXNode(
            role: "AXApplication", nodeId: "\(Self.app):root",
            frame: Rect(origin: Point(x: 0, y: 0), size: Size(width: 402, height: 874)),
            children: [button(Self.app, "page", 20, 130), button(Self.sheet, "share", 20, 130)])
        let placed = tree.placed(by: ["700:1700000000-1": AXRemoteFrames.Shift(x: 9, y: 479)])

        #expect(placed.children[0].frame.origin == Point(x: 20, y: 130))
        #expect(placed.children[1].frame.origin == Point(x: 29, y: 609))
    }
}

extension Rect {
    fileprivate func holdsLocal(_ point: Point) -> Bool {
        point.x >= origin.x && point.x <= origin.x + size.width
            && point.y >= origin.y && point.y <= origin.y + size.height
    }
}
