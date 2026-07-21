import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// Orchestration coverage for `SimctlLocation` — argv assembly + the
/// `Subprocess` exit handshake. The irreducible `xcrun` spawn lives in
/// `HostSubprocess` (integration-only), so every branch here is driven
/// through `MockSubprocess`.
@Suite("SimctlLocation")
struct SimctlLocationTests {

    final class Captures: @unchecked Sendable {
        var executable: URL?
        var arguments: [String]?
        var ran = false
    }

    private func makeLocation(exitCode: Int32 = 0) -> (SimctlLocation, Captures) {
        let sub = MockSubprocess()
        let captures = Captures()
        given(sub).run(
            executable: .any, arguments: .any, onBytes: .any, onExit: .any
        ).willProduce { exe, args, _, onExit in
            captures.ran = true
            captures.executable = exe
            captures.arguments = args
            onExit(exitCode)
        }
        given(sub).terminate().willReturn()
        return (SimctlLocation(udid: "U", subprocess: sub), captures)
    }

    @Test func `set spawns xcrun simctl location set with the lat,lon argument`() async throws {
        let (location, captures) = makeLocation()
        try await location.set(Coordinate(latitude: 37.3318, longitude: -122.0312)!)

        #expect(captures.executable == URL(fileURLWithPath: "/usr/bin/xcrun"))
        #expect(captures.arguments == ["simctl", "location", "U", "set", "37.3318,-122.0312"])
    }

    @Test func `start spawns xcrun simctl location start with the route argv`() async throws {
        let (location, captures) = makeLocation()
        let route = LocationRoute(
            waypoints: [
                Coordinate(latitude: 37.629538, longitude: -122.395733)!,
                Coordinate(latitude: 40.628083, longitude: -73.768254)!,
            ],
            speed: 260,
            distance: 1000
        )!
        try await location.start(route)

        #expect(captures.arguments == [
            "simctl", "location", "U", "start",
            "--speed=260", "--distance=1000",
            "37.629538,-122.395733", "40.628083,-73.768254",
        ])
    }

    @Test func `clear spawns xcrun simctl location clear`() async throws {
        let (location, captures) = makeLocation()
        try await location.clear()
        #expect(captures.arguments == ["simctl", "location", "U", "clear"])
    }

    @Test func `a non-zero simctl exit propagates as a location failure`() async {
        let (location, _) = makeLocation(exitCode: 3)
        var caught: LocationError?
        do {
            try await location.clear()
        } catch {
            caught = error as? LocationError
        }
        #expect(caught == .simctlFailed(status: 3))
    }
}
