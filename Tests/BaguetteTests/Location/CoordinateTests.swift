import Testing
import Foundation
@testable import BaguetteCore

/// Pure-value coverage for `Coordinate` — the validated lat/lon pair and
/// its projection to the `"<lat>,<lon>"` argument simctl expects. simctl
/// mandates `.` as the decimal separator and `,` as the field separator,
/// so the projection MUST stay locale-independent (a German locale's
/// `","` decimal comma would otherwise split the pair into garbage).
@Suite("Coordinate")
struct CoordinateTests {

    @Test func `projects to a dot-decimal comma-separated argument`() {
        let c = Coordinate(latitude: 37.3318, longitude: -122.0312)
        #expect(c?.argument == "37.3318,-122.0312")
    }

    @Test func `accepts the extremes of the valid range`() {
        #expect(Coordinate(latitude: 90, longitude: 180) != nil)
        #expect(Coordinate(latitude: -90, longitude: -180) != nil)
    }

    @Test func `rejects an out-of-range latitude`() {
        #expect(Coordinate(latitude: 91, longitude: 0) == nil)
        #expect(Coordinate(latitude: -90.1, longitude: 0) == nil)
    }

    @Test func `rejects an out-of-range longitude`() {
        #expect(Coordinate(latitude: 0, longitude: 181) == nil)
        #expect(Coordinate(latitude: 0, longitude: -180.5) == nil)
    }

    @Test func `parses a lat,lon token`() {
        #expect(Coordinate(token: "37.3318,-122.0312")
            == Coordinate(latitude: 37.3318, longitude: -122.0312))
    }

    @Test func `rejects a malformed or out-of-range token`() {
        #expect(Coordinate(token: "37.3318") == nil)
        #expect(Coordinate(token: "a,b") == nil)
        #expect(Coordinate(token: "120,0") == nil)
    }

    @Test func `serialises to a JSON object the route body and panel share`() {
        let c = Coordinate(latitude: 37.3318, longitude: -122.0312)
        #expect(c?.jsonString == "{\"latitude\":37.3318,\"longitude\":-122.0312}")
    }

    // MARK: - Projection along a bearing
    //
    // The great-circle destination formula, which `LocationWalk` uses to
    // place the far waypoint of a joystick's route. Unlike the
    // initialisers, this never fails: `asin` can't leave [-90, 90], and
    // the longitude is wrapped back onto [-180, 180] rather than
    // overflowing past the antimeridian.

    @Test func `projects due east from the equator along the equator`() {
        // At the equator an eastward great circle IS the equator, so the
        // whole 1 km lands in longitude: 1000 m / 6371008.8 m earth radius
        // = 1.569618e-4 rad = 0.0089926°.
        let start = Coordinate(latitude: 0, longitude: 0)!
        let end = start.projected(bearing: Bearing(degrees: 90), metres: 1000)
        #expect(abs(end.latitude) < 1e-9)
        #expect(abs(end.longitude - 0.0089926) < 1e-6)
    }

    @Test func `projects due north purely into latitude`() {
        let start = Coordinate(latitude: 37.3349, longitude: -122.0090)!
        let end = start.projected(bearing: Bearing(degrees: 0), metres: 1000)
        #expect(abs(end.latitude - 37.343893) < 1e-5)
        #expect(abs(end.longitude - (-122.0090)) < 1e-9)
    }

    @Test func `projects due south by decreasing latitude`() {
        let start = Coordinate(latitude: 37.3349, longitude: -122.0090)!
        let end = start.projected(bearing: Bearing(degrees: 180), metres: 1000)
        #expect(abs(end.latitude - 37.325907) < 1e-5)
        #expect(abs(end.longitude - (-122.0090)) < 1e-9)
    }

    @Test func `stands still when projected no distance`() {
        let start = Coordinate(latitude: 37.3349, longitude: -122.0090)!
        let end = start.projected(bearing: Bearing(degrees: 123), metres: 0)
        #expect(abs(end.latitude - start.latitude) < 1e-12)
        #expect(abs(end.longitude - start.longitude) < 1e-12)
    }

    @Test func `wraps longitude back onto the circle across the antimeridian`() {
        // Walking east off 179.999° must land at -179.992°, not 180.008° —
        // an unwrapped value would fail `Coordinate`'s own ±180 range.
        let start = Coordinate(latitude: 0, longitude: 179.999)!
        let end = start.projected(bearing: Bearing(degrees: 90), metres: 1000)
        #expect(abs(end.longitude - (-179.9920074)) < 1e-6)
        #expect(Coordinate(latitude: end.latitude, longitude: end.longitude) != nil)
    }

    @Test func `stays a valid coordinate when projected over the pole`() {
        // 500 km due north from 88°N crosses the pole and comes back down
        // the far side; latitude must stay inside ±90.
        let start = Coordinate(latitude: 88, longitude: 0)!
        let end = start.projected(bearing: Bearing(degrees: 0), metres: 500_000)
        #expect(end.latitude <= 90 && end.latitude >= -90)
        #expect(Coordinate(latitude: end.latitude, longitude: end.longitude) != nil)
    }
}
