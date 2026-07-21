import Testing
import Foundation
@testable import BaguetteCore

/// One trusted bakery measured against what its remote holds now.
/// Pure — the network round-trip is the caller's problem, so every
/// state is driven by feeding a head in.
@Suite("BakeryUpdate")
struct BakeryUpdateTests {

    @Test func `a bakery still on its pinned commit is up to date`() {
        let update = BakeryUpdate(id: "github.com/acme/tools", pinned: "abc123", head: "abc123")
        #expect(update.state == .upToDate)
    }

    @Test func `a bakery whose remote has moved has an update available`() {
        let update = BakeryUpdate(id: "github.com/acme/tools", pinned: "abc123", head: "def456")
        #expect(update.state == .available)
    }

    @Test func `a remote we could not reach is unknown, never up to date`() {
        // The failure that matters: reporting "up to date" because the
        // network was down tells the user the opposite of the truth.
        let update = BakeryUpdate(id: "github.com/acme/tools", pinned: "abc123", head: nil)
        #expect(update.state == .unreachable)
    }

    @Test func `only the moved ones are worth reporting`() {
        let updates = [
            BakeryUpdate(id: "a", pinned: "1", head: "1"),
            BakeryUpdate(id: "b", pinned: "1", head: "2"),
            BakeryUpdate(id: "c", pinned: "1", head: nil),
        ]
        // Unreachable counts as needing attention: it's the one case
        // where we genuinely don't know.
        #expect(updates.filter { $0.state != .upToDate }.map(\.id) == ["b", "c"])
    }

    // MARK: - how it reads

    @Test func `an available update names both commits so the change is visible`() {
        let line = BakeryUpdate(id: "github.com/acme/tools", pinned: "abc123def", head: "999888777").line
        #expect(line.contains("github.com/acme/tools"))
        #expect(line.contains("abc123d"))
        #expect(line.contains("9998887"))
    }

    @Test func `an unreachable bakery says so rather than showing a blank commit`() {
        let line = BakeryUpdate(id: "github.com/acme/tools", pinned: "abc123def", head: nil).line
        #expect(line.lowercased().contains("could not reach"))
    }
}
