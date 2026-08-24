import Testing
@testable import BaguetteCore

/// Both planes address a **constant**. A HID target is only valid if
/// some create-service message registered it, so it is never computed —
/// not from a screen id, not from a plist, not from anything.
@Suite("DisplayTouchTarget")
struct DisplayTouchTargetTests {

    @Test func `phone always uses the integrated digitizer constant`() {
        let target = DisplayTouchTarget.resolve(
            kind: .phone,
            connectedScreenId: 1,
            derive: { _ in 0xDEAD_BEEF }
        )
        #expect(target == IndigoHIDTouchTarget.phone)
    }

    /// The external plane addresses the CarPlay **service**, which
    /// registers at one fixed target — not at anything derived from the
    /// screen it happens to be showing on.
    ///
    /// Deriving it from the connected screen id is what restarted the
    /// guest, and `SimHIDVirtualServiceManager` says so in as many
    /// words when the event arrives:
    ///
    ///     *** Terminating app due to uncaught exception
    ///     'NSInternalInconsistencyException', reason: 'Encountered HID
    ///     event with unexpected target 1073741826 not in known targets:
    ///     ( 50, 13, 11, 53, 51, 302, 300, 1, 14, 60, 12, 100, 54,
    ///       1073741825, 301 )'
    ///
    /// `1073741826` is `0x40000002` — screen id 2, dutifully derived
    /// by `IndigoHIDTargetForScreen`, and registered by nothing.
    ///
    /// The real target is the `1` sitting quietly in that list. The
    /// guest keys its registry on the raw targetID the create message
    /// carries at `[0x40]`, which the host hardcodes to `1`:
    ///
    ///     allServices[ numberWithUnsignedInt:(targetID) ] = service
    ///
    /// Alongside it sit `50` (`0x32`, phone), `53` (`0x35`, pointer) and
    /// `54` (`0x36`, mouse) — every entry is a service something
    /// explicitly created, and every one is a constant, never a
    /// computation.
    @Test func `carPlay addresses the service target, whatever screen it is on`() {
        for screenId in [UInt32(2), 3, 204] {
            #expect(
                DisplayTouchTarget.resolve(
                    kind: .carPlay,
                    connectedScreenId: screenId,
                    derive: { $0 | 0x4000_0000 }
                ) == IndigoHIDTouchTarget.carPlay
            )
        }
        #expect(IndigoHIDTouchTarget.carPlay == 1)
        #expect(IndigoHIDTouchTarget.carPlay != IndigoHIDTouchTarget.phone)
    }

    /// The screen id is no longer an input to the answer, so the
    /// derivation is not consulted at all.
    @Test func `carPlay never derives a target from the screen`() {
        var derived = false
        _ = DisplayTouchTarget.resolve(
            kind: .carPlay,
            connectedScreenId: 3,
            derive: { _ in derived = true; return 0x4000_0003 }
        )
        #expect(!derived)
    }

    // MARK: - probe override

    /// Finding the right CarPlay target is a search, and the guest only
    /// publishes the registered set when it rejects one. An env
    /// override makes a candidate a restart rather than a rebuild.
    @Test func `an override replaces the CarPlay target`() {
        #expect(
            DisplayTouchTarget.resolve(
                kind: .carPlay, connectedScreenId: 2,
                derive: { _ in nil }, override: 302
            ) == 302
        )
    }

    /// The phone's digitizer is not part of the search.
    @Test func `an override never touches the phone plane`() {
        #expect(
            DisplayTouchTarget.resolve(
                kind: .phone, connectedScreenId: 1,
                derive: { _ in nil }, override: 302
            ) == IndigoHIDTouchTarget.phone
        )
    }

    @Test func `an override parses decimal and hex`() {
        #expect(DisplayTouchTarget.parseOverride("302") == 302)
        #expect(DisplayTouchTarget.parseOverride("0x12e") == 302)
        #expect(DisplayTouchTarget.parseOverride("0X40000001") == 0x4000_0001)
        #expect(DisplayTouchTarget.parseOverride("  302  ") == 302)
    }

    /// A typo must not become a number. Every unregistered target is one
    /// that kills the guest, so "unparseable" has to mean "use the
    /// known-good constant", never "use zero".
    @Test func `nonsense is ignored rather than turned into a target`() {
        for raw in ["", "   ", "abc", "0x", "3 0 2", "-1", "0xZZ"] {
            #expect(DisplayTouchTarget.parseOverride(raw) == nil, "\(raw)")
        }
        #expect(DisplayTouchTarget.parseOverride(nil) == nil)
    }

    /// The override is a *probe*, and the set it probes is the one the
    /// guest published when it threw. A number outside that set is
    /// precisely the unregistered target this whole type exists to keep
    /// out, so a typo in an env var must not be the thing that takes
    /// `backboardd` down.
    @Test func `an override outside the registered set is refused`() {
        for raw in ["0x40000002", "1073741826", "2", "999", "0x0"] {
            #expect(DisplayTouchTarget.parseOverride(raw) == nil, "\(raw)")
        }
    }

    /// And a refused override leaves the plane on the constant it would
    /// have used anyway, rather than on nothing.
    @Test func `an unregistered override leaves CarPlay on its own service`() {
        #expect(
            DisplayTouchTarget.resolve(
                kind: .carPlay, connectedScreenId: 2,
                derive: { _ in nil },
                override: DisplayTouchTarget.parseOverride("0x40000002")
            ) == IndigoHIDTouchTarget.carPlay
        )
    }

    /// Everything the guest named as registered, so a sweep can be
    /// driven from the list rather than from memory.
    @Test func `the probe list holds only registered targets`() {
        #expect(IndigoHIDTouchTarget.knownProbeTargets.contains(IndigoHIDTouchTarget.phone))
        #expect(IndigoHIDTouchTarget.knownProbeTargets.contains(IndigoHIDTouchTarget.carPlay))
        #expect(!IndigoHIDTouchTarget.knownProbeTargets.contains(0x4000_0002))
    }

    @Test func `phone is unaffected by the absent screen id`() {
        let target = DisplayTouchTarget.resolve(
            kind: .phone,
            connectedScreenId: 0,
            derive: { _ in nil }
        )
        #expect(target == IndigoHIDTouchTarget.phone)
    }
}
