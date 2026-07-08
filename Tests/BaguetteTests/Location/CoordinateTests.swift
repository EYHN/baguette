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
}
