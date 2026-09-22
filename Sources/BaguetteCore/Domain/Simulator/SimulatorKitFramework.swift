import Foundation

/// Where `SimulatorKit.framework` lives inside an Xcode install.
///
/// Xcode ≤26 ships it under the developer directory, in
/// `Contents/Developer/Library/PrivateFrameworks/`. Xcode 27 moved it
/// up a level into `Contents/SharedFrameworks/` — a *sibling* of
/// `Contents/Developer`, so it can no longer be reached by appending to
/// the path `xcode-select -p` reports. Baguette hardcoded the old
/// location at every `dlopen` site, which is why a machine whose only
/// Xcode is 27 can't drive a simulator at all (issue #28).
///
/// Both layouts are probed here, oldest-first, so an Xcode 26 install
/// resolves to exactly the path it always did.
enum SimulatorKitFramework {

    private static let suffix = "SimulatorKit.framework/SimulatorKit"

    /// Every location SimulatorKit is known to occupy, in probe order.
    ///
    /// Exposed separately from `path(developerDir:exists:)` so failure
    /// diagnostics can list what was actually searched rather than
    /// echoing a single path the user never had.
    static func candidatePaths(developerDir: String) -> [String] {
        // `Contents/Developer` → `Contents`. Resolved by trimming rather
        // than by appending `..` so the path that reaches a log message
        // is the one a user can paste into `ls`.
        let contents = (developerDir as NSString).deletingLastPathComponent
        return [
            (developerDir as NSString)
                .appendingPathComponent("Library/PrivateFrameworks/\(suffix)"),
            (contents as NSString)
                .appendingPathComponent("SharedFrameworks/\(suffix)"),
        ]
    }

    /// The first known location that exists, or `nil` when this Xcode
    /// carries no SimulatorKit at all.
    ///
    /// `exists` is injected so resolution order is unit-provable without
    /// either Xcode version installed.
    static func path(
        developerDir: String,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String? {
        candidatePaths(developerDir: developerDir).first(where: exists)
    }

    /// The major version of the Xcode whose SimulatorKit is in use, from
    /// the `DTXcode` stamp in its Info.plist ("2700" is Xcode 27.0).
    static func xcodeMajor(dtXcode: String?) -> Int? {
        guard let dtXcode, let stamp = Int(dtXcode), stamp >= 100 else { return nil }
        return stamp / 100
    }

    /// Read once: a process loads one SimulatorKit.
    static let hostXcodeMajor: Int? = {
        guard let binary = path(developerDir: CoreSimulators.developerDir()) else { return nil }
        let framework = (binary as NSString).deletingLastPathComponent
        for resources in ["Resources", "Versions/A/Resources"] {
            let plist = "\(framework)/\(resources)/Info.plist"
            if let info = NSDictionary(contentsOfFile: plist) {
                return xcodeMajor(dtXcode: info["DTXcode"] as? String)
            }
        }
        return nil
    }()
}
