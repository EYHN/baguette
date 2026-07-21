import Foundation

/// What we read from a CoreSimulator device-type's `profile.plist`.
/// Today we only need the `chromeIdentifier` to find the matching
/// DeviceKit chrome bundle, so the value carries just that — keeps
/// the type honest. New fields (e.g. `mainScreenScale`) get added the
/// moment a caller actually needs them.
struct DeviceProfile: Equatable, Sendable {
    /// Bare bundle name like `"phone11"` or `"tablet5"`. The plist
    /// stores the full bundle id (`com.apple.dt.devicekit.chrome.phone11`);
    /// we strip the prefix at parse time so the rest of the system
    /// works in directory-name space.
    let chromeIdentifier: String
    /// Screen size in 1x points. Used by 9-slice chrome composition to
    /// size the inner canvas area, since DeviceKit's `Screen.pdf` is a
    /// meaningless 1×1 marker. `nil` when neither source carries one.
    ///
    /// Two sources, because Xcode 27 moved the numbers. Xcode ≤26 put
    /// `mainScreenWidth` / `mainScreenHeight` / `mainScreenScale` on the
    /// profile itself; Xcode 27 dropped all three (124 of 124 device
    /// types carry them on 26, 0 of 124 on 27) and publishes the same
    /// values in a sibling `capabilities.plist` instead.
    let screenSize: Size?

    static func parsing(
        plistData data: Data,
        capabilitiesData: Data? = nil
    ) throws -> DeviceProfile {
        let raw: Any
        do {
            raw = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            )
        } catch {
            throw DeviceProfileParseError.malformedPlist
        }
        guard let dict = raw as? [String: Any] else {
            throw DeviceProfileParseError.malformedPlist
        }
        guard let fullID = dict["chromeIdentifier"] as? String else {
            throw DeviceProfileParseError.missingChromeIdentifier
        }

        let prefix = "com.apple.dt.devicekit.chrome."
        let bare = fullID.hasPrefix(prefix)
            ? String(fullID.dropFirst(prefix.count))
            : fullID

        return DeviceProfile(
            chromeIdentifier: bare,
            screenSize: parseScreenSize(dict)
                ?? capabilitiesData.flatMap(parseIntegratedDisplay)
        )
    }

    /// Xcode 27's `capabilities.plist` → `capabilities.displays`, a list
    /// describing every panel the device can drive. Only the
    /// `integrated` entry is the device's own screen: the others are
    /// `tvOut` and `carPlay` (both 720×480) and a `scene` entry at
    /// 7680×4320 for resizable windows. Sizing a bezel off any of those
    /// would be silently, wildly wrong, so the type is matched
    /// explicitly rather than taking the first element.
    private static func parseIntegratedDisplay(_ data: Data) -> Size? {
        guard let raw = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ),
              let root = raw as? [String: Any],
              let capabilities = root["capabilities"] as? [String: Any],
              let displays = capabilities["displays"] as? [[String: Any]],
              let panel = displays.first(where: {
                  $0["displayType"] as? String == "integrated"
              })
        else { return nil }
        return parseDisplaySize(panel)
    }

    /// Same arithmetic as `parseScreenSize`, over the capabilities
    /// spelling of the keys.
    private static func parseDisplaySize(_ dict: [String: Any]) -> Size? {
        guard let w = dict["width"] as? Double,
              let h = dict["height"] as? Double,
              let s = dict["scale"] as? Double,
              s > 0
        else { return nil }
        return Size(width: w / s, height: h / s)
    }

    /// Plist values are NSNumber-bridged; `as? Double` covers integer
    /// and float literals alike. All three keys must be present and the
    /// scale non-zero — anything else returns nil rather than producing
    /// a degenerate size.
    private static func parseScreenSize(_ dict: [String: Any]) -> Size? {
        guard let w = dict["mainScreenWidth"] as? Double,
              let h = dict["mainScreenHeight"] as? Double,
              let s = dict["mainScreenScale"] as? Double,
              s > 0
        else { return nil }
        return Size(width: w / s, height: h / s)
    }
}

enum DeviceProfileParseError: Error, Equatable {
    case malformedPlist
    case missingChromeIdentifier
}
