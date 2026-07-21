import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// Handler-level coverage for the interface routes. As with the
/// status-bar routes, the pure parse + dispatch helpers are tested
/// rather than the Hummingbird `Response` wrappers — every branch is
/// driven with `MockSimulators` + `MockInterface`.
@Suite("Server interface routes")
struct InterfaceRoutesTests {

    // MARK: - parsing the request

    @Test func `an update body names any subset of the three settings`() {
        // The three travel together but are set independently — a panel
        // flipping only dark mode shouldn't have to restate the rest.
        #expect(
            Server.parseInterfaceUpdate(json: #"{"appearance":"dark"}"#)
                == InterfaceUpdate(appearance: .dark)
        )
        #expect(
            Server.parseInterfaceUpdate(json: #"{"increaseContrast":"enabled"}"#)
                == InterfaceUpdate(increaseContrast: .enabled)
        )
        #expect(
            Server.parseInterfaceUpdate(json: #"{"contentSize":"increment"}"#)
                == InterfaceUpdate(contentSize: .increment)
        )
    }

    @Test func `an update body can carry all three at once`() {
        let json = #"{"appearance":"dark","increaseContrast":"enabled","contentSize":"accessibility-large"}"#
        #expect(Server.parseInterfaceUpdate(json: json) == InterfaceUpdate(
            appearance: .dark,
            increaseContrast: .enabled,
            contentSize: .size(.accessibilityLarge)
        ))
    }

    @Test func `a malformed body is refused`() {
        #expect(Server.parseInterfaceUpdate(json: "not json") == nil)
    }

    @Test func `a value that can only be read is refused at the door`() {
        // `unknown` is what a shut-down device *answers*. Echoing it
        // back as an instruction is a caller bug, and it fails here
        // rather than as a confusing simctl usage error.
        #expect(Server.parseInterfaceUpdate(json: #"{"appearance":"unknown"}"#) == nil)
        #expect(Server.parseInterfaceUpdate(json: #"{"contentSize":"unsupported"}"#) == nil)
        #expect(Server.parseInterfaceUpdate(json: #"{"increaseContrast":"maybe"}"#) == nil)
    }

    @Test func `an empty body sets nothing`() {
        // Distinguishable from a parse failure: valid JSON, nothing to do.
        #expect(Server.parseInterfaceUpdate(json: "{}") == InterfaceUpdate())
        #expect(InterfaceUpdate().isEmpty)
        #expect(!InterfaceUpdate(appearance: .dark).isEmpty)
    }

    // MARK: - reading

    @Test func `reading answers all three settings in one call`() async throws {
        let simulators = Self.simulators(
            appearance: .dark, contrast: .enabled, contentSize: .accessibilityLarge
        )
        guard case .ok(let json) = await Server.readInterface(udid: "U", simulators: simulators)
        else { Issue.record("expected .ok"); return }

        let parsed = try #require(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        #expect(parsed["appearance"] as? String == "dark")
        #expect(parsed["increaseContrast"] as? String == "enabled")
        #expect(parsed["contentSize"] as? String == "accessibility-large")
    }

    @Test func `a shut-down device answers unknown rather than failing the request`() async {
        // The panel needs to be able to say "boot the device" — which
        // it can only do if the read succeeds and reports unknown.
        let simulators = Self.simulators(
            appearance: .unknown, contrast: .unknown, contentSize: .unknown
        )
        guard case .ok(let json) = await Server.readInterface(udid: "U", simulators: simulators)
        else { Issue.record("expected .ok"); return }
        #expect(json.contains("\"appearance\":\"unknown\""))
    }

    @Test func `reading an unknown device is reported as such`() async {
        let simulators = MockSimulators()
        given(simulators).find(udid: .any).willReturn(nil)
        #expect(await Server.readInterface(udid: "nope", simulators: simulators) == .unknownDevice)
    }

    // MARK: - applying

    @Test func `applying dispatches only the settings the body named`() async {
        let interface = MockInterface()
        given(interface).setAppearance(.any).willReturn(())
        given(interface).setIncreaseContrast(.any).willReturn(())
        given(interface).setContentSize(.any).willReturn(())

        let outcome = await Server.applyInterface(
            udid: "U",
            update: InterfaceUpdate(appearance: .dark),
            simulators: Self.simulators(interface: interface)
        )

        #expect(outcome == .ok(applied: ["appearance"]))
        verify(interface).setAppearance(.value(.dark)).called(1)
        verify(interface).setIncreaseContrast(.any).called(0)
        verify(interface).setContentSize(.any).called(0)
    }

    @Test func `applying all three dispatches all three`() async {
        let interface = MockInterface()
        given(interface).setAppearance(.any).willReturn(())
        given(interface).setIncreaseContrast(.any).willReturn(())
        given(interface).setContentSize(.any).willReturn(())

        _ = await Server.applyInterface(
            udid: "U",
            update: InterfaceUpdate(
                appearance: .light, increaseContrast: .disabled, contentSize: .decrement
            ),
            simulators: Self.simulators(interface: interface)
        )

        verify(interface).setAppearance(.value(.light)).called(1)
        verify(interface).setIncreaseContrast(.value(.disabled)).called(1)
        verify(interface).setContentSize(.value(.decrement)).called(1)
    }

    @Test func `a failing spawn surfaces as a failure, not a silent success`() async {
        let interface = MockInterface()
        given(interface).setAppearance(.any).willThrow(InterfaceError.simctlFailed(status: 3))

        let outcome = await Server.applyInterface(
            udid: "U",
            update: InterfaceUpdate(appearance: .dark),
            simulators: Self.simulators(interface: interface)
        )
        guard case .failed(let message, let applied) = outcome else {
            Issue.record("expected .failed, got \(outcome)"); return
        }
        #expect(message.contains("3"))
        // Nothing landed before the very first setter threw.
        #expect(applied.isEmpty)
    }

    @Test func `a failure after an earlier success names what did apply`() async {
        // Each setting is its own spawn, so a three-field body is three
        // chances to fail halfway. A bare failure would tell the caller
        // nothing changed, when in fact the appearance already had.
        let interface = MockInterface()
        given(interface).setAppearance(.any).willReturn(())
        given(interface).setIncreaseContrast(.any)
            .willThrow(InterfaceError.simctlFailed(status: 3))
        given(interface).setContentSize(.any).willReturn(())

        let outcome = await Server.applyInterface(
            udid: "U",
            update: InterfaceUpdate(
                appearance: .dark, increaseContrast: .enabled, contentSize: .increment
            ),
            simulators: Self.simulators(interface: interface)
        )
        guard case .failed(let message, let applied) = outcome else {
            Issue.record("expected .failed, got \(outcome)"); return
        }
        #expect(applied == ["appearance"])
        #expect(message.contains("3"))
        // The setting after the failure is not attempted — a body is
        // applied in order and stops where it broke.
        verify(interface).setContentSize(.any).called(0)
    }

    @Test func `a wholly successful apply names every setting it landed`() async {
        let interface = MockInterface()
        given(interface).setAppearance(.any).willReturn(())
        given(interface).setIncreaseContrast(.any).willReturn(())
        given(interface).setContentSize(.any).willReturn(())

        let outcome = await Server.applyInterface(
            udid: "U",
            update: InterfaceUpdate(
                appearance: .light, increaseContrast: .disabled, contentSize: .decrement
            ),
            simulators: Self.simulators(interface: interface)
        )
        guard case .ok(let applied) = outcome else {
            Issue.record("expected .ok, got \(outcome)"); return
        }
        #expect(applied == ["appearance", "increaseContrast", "contentSize"])
    }

    @Test func `the applied answer is the shape a caller can act on`() throws {
        // Used when the post-change read fails: the settings landed,
        // but the device won't say what it now reads as. `{"ok":true}`
        // claimed success in a shape the caller couldn't use.
        let parsed = try #require(
            JSONSerialization.jsonObject(
                with: Data(Server.appliedJSON(["appearance"], error: "simctl exited 3").utf8)
            ) as? [String: Any]
        )
        #expect(parsed["applied"] as? [String] == ["appearance"])
        #expect(parsed["error"] as? String == "simctl exited 3")
        #expect(parsed["ok"] as? Bool == false)

        let clean = try #require(
            JSONSerialization.jsonObject(
                with: Data(Server.appliedJSON(["appearance", "contentSize"]).utf8)
            ) as? [String: Any]
        )
        #expect(clean["applied"] as? [String] == ["appearance", "contentSize"])
        #expect(clean["ok"] as? Bool == true)
        #expect(clean["error"] == nil)
    }

    @Test func `applying to an unknown device is reported as such`() async {
        let simulators = MockSimulators()
        given(simulators).find(udid: .any).willReturn(nil)
        let outcome = await Server.applyInterface(
            udid: "nope", update: InterfaceUpdate(appearance: .dark), simulators: simulators
        )
        #expect(outcome == .unknownDevice)
    }

    // MARK: - helpers

    static func simulators(
        appearance: InterfaceAppearance = .light,
        contrast: InterfaceContrast = .disabled,
        contentSize: ContentSize = .large
    ) -> MockSimulators {
        let interface = MockInterface()
        given(interface).appearance().willReturn(appearance)
        given(interface).increaseContrast().willReturn(contrast)
        given(interface).contentSize().willReturn(contentSize)
        return simulators(interface: interface)
    }

    static func simulators(interface: MockInterface) -> MockSimulators {
        let sim = MockSimulator()
        given(sim).interface().willReturn(interface)
        let simulators = MockSimulators()
        given(simulators).find(udid: .any).willReturn(sim)
        return simulators
    }
}
