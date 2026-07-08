import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// Handler-level coverage for the location routes. As with the
/// status-bar routes, we test the pure parse + dispatch helpers
/// (`parseLocationRequest`, `applyLocation`, `clearLocation`) rather than
/// the Hummingbird `Response` wrappers — every branch is driven with
/// `MockSimulators` + `MockLocation`.
@Suite("Server location routes")
struct LocationRoutesTests {

    // MARK: - parse

    @Test func `parseLocationRequest reads a single point body`() {
        #expect(Server.parseLocationRequest(json: #"{"latitude":37.3318,"longitude":-122.0312}"#)
            == .point(Coordinate(latitude: 37.3318, longitude: -122.0312)!))
    }

    @Test func `parseLocationRequest reads a route body with tuning`() {
        let json = """
        {"waypoints":[{"latitude":37.6,"longitude":-122.4},
                      {"latitude":40.6,"longitude":-73.8}],
         "speed":260,"distance":1000}
        """
        #expect(Server.parseLocationRequest(json: json) == .route(LocationRoute(
            waypoints: [
                Coordinate(latitude: 37.6, longitude: -122.4)!,
                Coordinate(latitude: 40.6, longitude: -73.8)!,
            ],
            speed: 260, distance: 1000
        )!))
    }

    @Test func `parseLocationRequest returns nil for malformed JSON`() {
        #expect(Server.parseLocationRequest(json: "not json") == nil)
    }

    @Test func `parseLocationRequest returns nil for an out-of-range point`() {
        #expect(Server.parseLocationRequest(json: #"{"latitude":120,"longitude":0}"#) == nil)
    }

    @Test func `parseLocationRequest returns nil for a one-waypoint route`() {
        #expect(Server.parseLocationRequest(json: #"{"waypoints":[{"latitude":1,"longitude":2}]}"#) == nil)
    }

    // MARK: - apply

    @Test func `applyLocation sets a single point on the simulator`() async {
        let host = MockSimulators()
        let sim = MockSimulator()
        let location = MockLocation()
        given(host).find(udid: .value("U")).willReturn(sim)
        given(sim).location().willReturn(location)
        given(location).set(.any).willReturn(())

        let outcome = await Server.applyLocation(
            udid: "U", body: #"{"latitude":1.5,"longitude":2.5}"#, simulators: host
        )
        #expect(outcome == .ok)
        verify(location).set(.value(Coordinate(latitude: 1.5, longitude: 2.5)!)).called(1)
    }

    @Test func `applyLocation starts a route on the simulator`() async {
        let host = MockSimulators()
        let sim = MockSimulator()
        let location = MockLocation()
        given(host).find(udid: .value("U")).willReturn(sim)
        given(sim).location().willReturn(location)
        given(location).start(.any).willReturn(())

        let json = #"{"waypoints":[{"latitude":1,"longitude":2},{"latitude":3,"longitude":4}]}"#
        let outcome = await Server.applyLocation(udid: "U", body: json, simulators: host)
        #expect(outcome == .ok)
        verify(location).start(.any).called(1)
    }

    @Test func `applyLocation reports unknownDevice when the simulator is missing`() async {
        let host = MockSimulators()
        given(host).find(udid: .value("ghost")).willReturn(nil)
        let outcome = await Server.applyLocation(
            udid: "ghost", body: #"{"latitude":1,"longitude":2}"#, simulators: host
        )
        #expect(outcome == .unknownDevice)
    }

    @Test func `applyLocation reports invalidBody for malformed JSON`() async {
        let host = MockSimulators()
        let sim = MockSimulator()
        given(host).find(udid: .value("U")).willReturn(sim)
        #expect(await Server.applyLocation(udid: "U", body: "{", simulators: host) == .invalidBody)
    }

    @Test func `applyLocation reports dispatchFailed when simctl throws`() async {
        let host = MockSimulators()
        let sim = MockSimulator()
        let location = MockLocation()
        given(host).find(udid: .value("U")).willReturn(sim)
        given(sim).location().willReturn(location)
        given(location).set(.any).willThrow(LocationError.simctlFailed(status: 1))

        let outcome = await Server.applyLocation(
            udid: "U", body: #"{"latitude":1,"longitude":2}"#, simulators: host
        )
        #expect(outcome == .dispatchFailed)
    }

    // MARK: - clear

    @Test func `clearLocation clears the simulated location`() async {
        let host = MockSimulators()
        let sim = MockSimulator()
        let location = MockLocation()
        given(host).find(udid: .value("U")).willReturn(sim)
        given(sim).location().willReturn(location)
        given(location).clear().willReturn(())

        #expect(await Server.clearLocation(udid: "U", simulators: host) == .ok)
        verify(location).clear().called(1)
    }

    @Test func `clearLocation reports unknownDevice for an empty udid`() async {
        let host = MockSimulators()
        #expect(await Server.clearLocation(udid: "", simulators: host) == .unknownDevice)
    }
}
