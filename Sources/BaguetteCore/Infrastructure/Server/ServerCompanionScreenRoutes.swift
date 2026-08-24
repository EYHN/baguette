import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdWebSocket
import NIOCore

/// The companion-screens route — what the focus-mode rail asks before
/// it offers anything. Kept out of `Server.swift`'s main body for the
/// same reason the interface and plugin routes are: that file's
/// router-builder inference grinds once too many closures share one
/// function.
extension Server {

    /// `GET /simulators/:udid/companion-screens.json`
    ///
    /// Browser-facing only. It reports what the host has attached to a
    /// device, which is the sort of thing a plugin should have to
    /// declare a capability for, and no capability covers it yet — so
    /// it rides the browser-trust check alone.
    func registerCompanionScreenRoutes(
        on router: Router<BasicWebSocketRequestContext>,
        rejectUntrustedBrowser: @escaping @Sendable (Request) -> Response?
    ) {
        let simulators = self.simulators

        router.get("/simulators/:udid/companion-screens.json") { r, _ in
            if let rejected = rejectUntrustedBrowser(r) { return rejected }
            switch Self.readCompanionScreens(udid: Self.udidParam(r), simulators: simulators) {
            case .ok(let json):
                return Self.jsonResponse(json)
            case .unknownDevice:
                return Self.pluginError("unknown udid: \(Self.udidParam(r))", status: .notFound)
            }
        }

        // Drives Simulator.app's menus, so it stays browser-only and
        // out of reach of plugins — a capability that can click another
        // application's UI is not one to hand out with a manifest line.
        // Three segments, not `…/companion-screens/carplay`: `udidParam`
        // reads the udid positionally as the second-to-last one.
        router.post("/simulators/:udid/carplay-display") { r, _ in
            if let rejected = rejectUntrustedBrowser(r) { return rejected }
            switch Self.reattachCarPlay(udid: Self.udidParam(r), simulators: simulators) {
            case .ok(let json):
                return Self.jsonResponse(json)
            case .unknownDevice:
                return Self.pluginError("unknown udid: \(Self.udidParam(r))", status: .notFound)
            case .failed(let message):
                // The overwhelmingly common cause is macOS refusing the
                // Apple event, which is a permission the user grants
                // once — so say what to do, not just what broke.
                return Self.pluginError(
                    "could not drive Simulator.app: \(message). "
                        + "Grant Automation + Accessibility access to the terminal "
                        + "running baguette in System Settings → Privacy & Security.",
                    status: .internalServerError
                )
            }
        }
    }

    enum CompanionScreensOutcome: Equatable {
        case ok(String)
        case unknownDevice
    }

    enum CarPlayReattachOutcome: Equatable {
        /// The resulting availability, in the same shape the rail reads.
        case ok(String)
        case unknownDevice
        case failed(String)
    }

    /// Attach (or reattach) this device's CarPlay display, then say what
    /// it can do afterwards.
    ///
    /// The menu dance is baguette's to drive — it already raises the
    /// device's own window first, which is the step that goes wrong when
    /// a person does it by hand with the wrong simulator frontmost. What
    /// it can't promise is a framebuffer: the click can land and leave
    /// nothing to stream, so the answer is a fresh bind probe rather
    /// than `{"ok":true}`.
    static func reattachCarPlay(
        udid: String, simulators: any Simulators
    ) -> CarPlayReattachOutcome {
        guard let sim = simulators.find(udid: udid) else { return .unknownDevice }
        do {
            try sim.externalDisplays().reattachCarPlay()
        } catch {
            return .failed(String(describing: error))
        }
        switch readCompanionScreens(udid: udid, simulators: simulators) {
        case .ok(let json):   return .ok(json)
        case .unknownDevice:  return .unknownDevice
        }
    }

    /// What extra screens this device can show right now.
    ///
    /// CarPlay availability is a **bind**, not a name lookup.
    /// `ExternalDisplays.isCarPlayConnected` answers the easier question
    /// — does Connected Screens list something of that type — and a
    /// device can carry a registered CarPlay screen with no framebuffer
    /// behind it, left over from an enable whose host window has gone.
    /// The host is quite clear about it (`simctl screenshot` on that
    /// screen fails with "Timeout waiting for screen surfaces"), but the
    /// name is still in the list. Believing the name lights the rail and
    /// opens a pane that can never paint.
    ///
    /// So we ask the same `resolve()` the stream asks. If it can't bind,
    /// the stream couldn't either, and the useful answer is the
    /// instructions for attaching a working one.
    ///
    /// Only an unknown udid fails. Both probes answer "no" rather than
    /// throwing — a shutdown device resolves nothing, and an unreadable
    /// pairing table yields no watch — so a device that is merely off
    /// still gets a renderable answer instead of a 500 the rail would
    /// have to guess at.
    static func readCompanionScreens(
        udid: String, simulators: any Simulators
    ) -> CompanionScreensOutcome {
        guard let sim = simulators.find(udid: udid) else { return .unknownDevice }
        // The binding's own size, so the rail can name what it bound
        // rather than assume the menu attached a CarPlay-shaped screen.
        let screens = CompanionScreens(
            externalSize: (try? sim.displays().carPlay.resolve())?.size,
            watch: sim.watchPairing().watch
        )
        return .ok(screens.json)
    }
}
