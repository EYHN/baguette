import Foundation

/// Resolves the Indigo HID digitizer target for a display plane.
///
/// Both answers are constants, because a target is only valid if some
/// create-service message registered it — see `IndigoHIDTouchTarget`.
/// The plane picks *which* service to address; the screen it is
/// currently showing on has nothing to do with it.
///
/// `connectedScreenId` and `derive` are kept for the caller's shape and
/// deliberately unused for CarPlay. `IndigoHIDTargetForScreen` is a real
/// SimulatorKit export and it is tempting precisely because it looks
/// like the answer — it returns `0x40000000 | screenId`, a plausible
/// number that no service has registered. Sending there is what
/// restarted the guest.
enum DisplayTouchTarget {
    static func resolve(
        kind: DisplayKind,
        connectedScreenId: UInt32,
        derive: (UInt32) -> UInt32?,
        override: UInt32? = nil
    ) -> UInt32? {
        switch kind {
        case .phone:   return IndigoHIDTouchTarget.phone
        case .carPlay: return override ?? IndigoHIDTouchTarget.carPlay
        }
    }

    /// Parses a probe override — `BAGUETTE_CARPLAY_TARGET`, decimal or
    /// `0x`-prefixed. Exists because finding the right target is a
    /// search: the guest publishes the registered set only when it
    /// rejects one, and rebuilding between candidates is far slower
    /// than restarting with a different number.
    ///
    /// The search runs over `knownProbeTargets` and nowhere else, so
    /// that is what this accepts. Anything outside it — a typo, a
    /// number `IndigoHIDTargetForScreen` handed back, a guess — is by
    /// definition a target no service registered, and dispatching there
    /// is what takes `backboardd` and SpringBoard down. An env var is
    /// not a good place to be able to do that from.
    ///
    /// Rejected input yields `nil` rather than something arbitrary, so
    /// the caller falls back to the known-good constant.
    static func parseOverride(_ raw: String?) -> UInt32? {
        guard var text = raw?.trimmingCharacters(in: .whitespaces), !text.isEmpty else {
            return nil
        }
        var radix = 10
        if text.lowercased().hasPrefix("0x") {
            radix = 16
            text = String(text.dropFirst(2))
        }
        guard let target = UInt32(text, radix: radix),
              IndigoHIDTouchTarget.knownProbeTargets.contains(target)
        else {
            return nil
        }
        return target
    }
}
