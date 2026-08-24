import Foundation
import Testing

@testable import BaguetteCore

/// `simctl list pairs -j` is the host's whole pairing table, not one
/// device's. A phone finds its watch by looking for the pair whose
/// phone side carries its own udid; every other row on the machine
/// belongs to somebody else's phone.
@Suite("SimctlPairs")
struct SimctlPairsTests {

    private let pairsJSON = """
        {
          "pairs" : {
            "5F1B0A00-0000-0000-0000-00000000AAAA" : {
              "watch" : {
                "name" : "Apple Watch Series 11 (46mm)",
                "udid" : "WATCH-1",
                "state" : "Booted"
              },
              "phone" : {
                "name" : "iPhone 17 Pro",
                "udid" : "PHONE-1",
                "state" : "Booted"
              },
              "state" : "(active, disconnected)"
            },
            "5F1B0A00-0000-0000-0000-00000000BBBB" : {
              "watch" : {
                "name" : "Apple Watch Ultra 3",
                "udid" : "WATCH-2",
                "state" : "Shutdown"
              },
              "phone" : {
                "name" : "iPhone 17",
                "udid" : "PHONE-2",
                "state" : "Shutdown"
              },
              "state" : "(active, disconnected)"
            }
          }
        }
        """

    @Test func `a phone finds the watch on its own side of the pairs table`() {
        let watch = SimctlPairs.watch(pairedWith: "PHONE-2", in: pairsJSON)

        #expect(watch == PairedWatch(
            udid: "WATCH-2",
            name: "Apple Watch Ultra 3",
            state: .shutdown
        ))
    }

    @Test func `a booted watch carries its booted state`() {
        #expect(SimctlPairs.watch(pairedWith: "PHONE-1", in: pairsJSON)?.state == .booted)
    }

    @Test func `a phone that is nobody's pair has no watch`() {
        #expect(SimctlPairs.watch(pairedWith: "PHONE-3", in: pairsJSON) == nil)
    }

    @Test func `an empty pairs table has no watch`() {
        #expect(SimctlPairs.watch(pairedWith: "PHONE-1", in: #"{"pairs":{}}"#) == nil)
    }

    @Test func `output that isn't JSON has no watch`() {
        #expect(SimctlPairs.watch(pairedWith: "PHONE-1", in: "xcrun: error: unable to find") == nil)
    }

    @Test func `a pair missing either side is skipped rather than half-read`() {
        let partial = """
            {"pairs":{"P":{"phone":{"name":"iPhone 17","udid":"PHONE-1","state":"Booted"}}}}
            """
        #expect(SimctlPairs.watch(pairedWith: "PHONE-1", in: partial) == nil)
    }

    @Test func `a state the host prints but we don't model reads as shutdown`() {
        let odd = """
            {"pairs":{"P":{"phone":{"name":"iPhone","udid":"PHONE-1","state":"Booted"},
             "watch":{"name":"Apple Watch","udid":"WATCH-1","state":"Hibernating"}}}}
            """
        #expect(SimctlPairs.watch(pairedWith: "PHONE-1", in: odd)?.state == .shutdown)
    }

    @Test func `every state the host prints round-trips through its description`() {
        for state in [
            SimulatorState.creating, .shutdown, .booting, .booted, .shuttingDown,
        ] {
            #expect(SimulatorState.named(state.description) == state)
        }
    }
}
