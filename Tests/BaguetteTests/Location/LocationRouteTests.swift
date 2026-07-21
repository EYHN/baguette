import Testing
import Foundation
@testable import BaguetteCore

/// Pure-value coverage for `LocationRoute.startArguments` — the argv tail
/// handed to `xcrun simctl location <udid> start …`. simctl interpolates
/// a moving location between the waypoints; speed / distance / interval
/// tune how fast and how often updates fire. At least two waypoints are
/// required (one point is a `set`, not a route).
@Suite("LocationRoute")
struct LocationRouteTests {

    private func sf() -> Coordinate { Coordinate(latitude: 37.629538, longitude: -122.395733)! }
    private func nyc() -> Coordinate { Coordinate(latitude: 40.628083, longitude: -73.768254)! }

    @Test func `requires at least two waypoints`() {
        #expect(LocationRoute(waypoints: []) == nil)
        #expect(LocationRoute(waypoints: [sf()]) == nil)
        #expect(LocationRoute(waypoints: [sf(), nyc()]) != nil)
    }

    @Test func `a bare route emits only its waypoints`() {
        let route = LocationRoute(waypoints: [sf(), nyc()])
        #expect(route?.startArguments == ["37.629538,-122.395733", "40.628083,-73.768254"])
    }

    @Test func `speed distance and interval emit equals-form flags before the waypoints`() {
        let route = LocationRoute(
            waypoints: [sf(), nyc()],
            speed: 260,
            distance: 1000,
            interval: 2.5
        )
        #expect(route?.startArguments == [
            "--speed=260",
            "--distance=1000",
            "--interval=2.5",
            "37.629538,-122.395733",
            "40.628083,-73.768254",
        ])
    }

    @Test func `rejects a non-positive speed`() {
        #expect(LocationRoute(waypoints: [sf(), nyc()], speed: 0) == nil)
        #expect(LocationRoute(waypoints: [sf(), nyc()], speed: -5) == nil)
    }
}
