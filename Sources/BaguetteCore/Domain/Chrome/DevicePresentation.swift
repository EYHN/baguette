import Foundation

enum DeviceFormFactor: String, Equatable, Sendable {
    case phone
    case tablet
    case watch
    case tv
    case vision
    case unknown
}

struct ScreenCornerRadii: Equatable, Sendable {
    let topLeft: Double
    let topRight: Double
    let bottomLeft: Double
    let bottomRight: Double

    static let zero = ScreenCornerRadii(all: 0)

    init(
        topLeft: Double,
        topRight: Double,
        bottomLeft: Double,
        bottomRight: Double
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }

    init(all radius: Double) {
        self.init(
            topLeft: radius,
            topRight: radius,
            bottomLeft: radius,
            bottomRight: radius
        )
    }

    var uniformRadius: Double? {
        guard topLeft == topRight,
              topLeft == bottomLeft,
              topLeft == bottomRight
        else { return nil }
        return topLeft
    }

    var json: [String: Double] {
        [
            "topLeft": topLeft,
            "topRight": topRight,
            "bottomLeft": bottomLeft,
            "bottomRight": bottomRight,
        ]
    }
}

/// Device-type metadata needed to place a Simulator framebuffer. It is
/// independent of whether DeviceKit publishes a physical bezel for the
/// device, so frameless platforms still retain their real display bounds.
struct DevicePresentationProfile: Equatable, Sendable {
    let chromeIdentifier: String?
    /// `true` only when the identifier is a compatibility mapping for a
    /// device whose installed DeviceKit may legitimately omit the bundle.
    let chromeIsOptional: Bool
    let formFactor: DeviceFormFactor
    let screenSize: Size
    let screenScale: Double
    let screenCornerRadii: ScreenCornerRadii?
    let nativeOrientation: Double?

    static func parsing(
        plistData: Data,
        capabilitiesData: Data?,
        deviceName: String
    ) throws -> DevicePresentationProfile {
        let profile = try plistDictionary(plistData)
        let capabilities = capabilitiesData.flatMap(capabilitiesDictionary)
        let resolvedFormFactor = formFactor(
            capabilities?["idiom"] as? String,
            deviceName: deviceName
        )
        let display = displayDictionary(
            capabilities?["displays"] as? [[String: Any]],
            formFactor: resolvedFormFactor
        )

        guard let dimensions = display.flatMap(displayDimensions)
            ?? legacyDisplayDimensions(profile)
        else {
            throw DevicePresentationProfileParseError.missingDisplay
        }

        let declaredChromeIdentifier = normalizedChromeIdentifier(
            profile["chromeIdentifier"] as? String
        )
        let chromeIdentifier = declaredChromeIdentifier
            ?? (resolvedFormFactor == .tv ? "tv" : nil)

        return DevicePresentationProfile(
            chromeIdentifier: chromeIdentifier,
            chromeIsOptional:
                declaredChromeIdentifier == nil && resolvedFormFactor == .tv,
            formFactor: resolvedFormFactor,
            screenSize: dimensions.size,
            screenScale: dimensions.scale,
            screenCornerRadii: display.flatMap(screenCornerRadii),
            nativeOrientation: number(display?["nativeOrientation"])
        )
    }

    private static func plistDictionary(_ data: Data) throws -> [String: Any] {
        guard let raw = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ),
              let dictionary = raw as? [String: Any]
        else {
            throw DevicePresentationProfileParseError.malformedPlist
        }
        return dictionary
    }

    private static func capabilitiesDictionary(_ data: Data) -> [String: Any]? {
        guard let raw = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ),
              let root = raw as? [String: Any]
        else { return nil }
        return root["capabilities"] as? [String: Any]
    }

    private static func normalizedChromeIdentifier(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let prefix = "com.apple.dt.devicekit.chrome."
        return identifier.hasPrefix(prefix)
            ? String(identifier.dropFirst(prefix.count))
            : identifier
    }

    private static func formFactor(
        _ idiom: String?,
        deviceName: String
    ) -> DeviceFormFactor {
        switch idiom?.lowercased() {
        case "phone": return .phone
        case "pad", "tablet": return .tablet
        case "watch": return .watch
        case "tv": return .tv
        case "vision": return .vision
        default:
            if deviceName.hasPrefix("iPhone") { return .phone }
            if deviceName.hasPrefix("iPod") { return .phone }
            if deviceName.hasPrefix("iPad") { return .tablet }
            if deviceName.hasPrefix("Apple Watch") { return .watch }
            if deviceName.hasPrefix("Apple TV") { return .tv }
            if deviceName.hasPrefix("Apple Vision") { return .vision }
            return .unknown
        }
    }

    private static func displayDictionary(
        _ displays: [[String: Any]]?,
        formFactor: DeviceFormFactor
    ) -> [String: Any]? {
        guard let displays else { return nil }
        if let integrated = displays.first(where: {
            $0["displayType"] as? String == "integrated"
        }) {
            return integrated
        }
        if formFactor == .tv {
            return displays.first(where: {
                $0["displayType"] as? String == "tvOut"
            })
        }
        return nil
    }

    private static func displayDimensions(
        _ display: [String: Any]
    ) -> (size: Size, scale: Double)? {
        guard let width = number(display["width"]),
              let height = number(display["height"]),
              let scale = number(display["scale"]),
              width > 0,
              height > 0,
              scale > 0
        else { return nil }
        return (
            Size(width: width / scale, height: height / scale),
            scale
        )
    }

    private static func legacyDisplayDimensions(
        _ profile: [String: Any]
    ) -> (size: Size, scale: Double)? {
        guard let width = number(profile["mainScreenWidth"]),
              let height = number(profile["mainScreenHeight"]),
              let scale = number(profile["mainScreenScale"]),
              width > 0,
              height > 0,
              scale > 0
        else { return nil }
        return (
            Size(width: width / scale, height: height / scale),
            scale
        )
    }

    private static func screenCornerRadii(
        _ display: [String: Any]
    ) -> ScreenCornerRadii? {
        guard let topLeft = number(display["cornerRadiusUL"]),
              let topRight = number(display["cornerRadiusUR"]),
              let bottomLeft = number(display["cornerRadiusLL"]),
              let bottomRight = number(display["cornerRadiusLR"])
        else { return nil }
        return ScreenCornerRadii(
            topLeft: topLeft,
            topRight: topRight,
            bottomLeft: bottomLeft,
            bottomRight: bottomRight
        )
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }
}

enum DevicePresentationProfileParseError: Error, Equatable {
    case malformedPlist
    case missingDisplay
}

enum DevicePresentationResolveError: Error, Equatable {
    case chromeUnavailable(String)
}

/// A matched layout and optional DeviceKit bezel. Geometry and image bytes
/// are deliberately resolved together so consumers cannot pair a cached image
/// from one device size with another device's screen rectangle.
struct DevicePresentation: Equatable, Sendable {
    enum Style: String, Equatable, Sendable {
        case bezel
        case frameless
    }

    let style: Style
    let identifier: String?
    let formFactor: DeviceFormFactor
    let viewport: Size
    let screen: Rect
    let screenScale: Double
    let screenCornerRadii: ScreenCornerRadii
    let nativeOrientation: Double?
    let bezelPNG: Data?

    static func framed(
        profile: DevicePresentationProfile,
        assets: DeviceChromeAssets
    ) -> DevicePresentation {
        let margins = assets.buttonMargins
        let bareSize = Size(
            width: assets.composite.size.width - margins.left - margins.right,
            height: assets.composite.size.height
                - margins.top
                - margins.bottom
                - (assets.chrome.stand?.height ?? 0)
        )
        let bareScreen = assets.chrome.screenRect(in: bareSize)
        let screen = Rect(
            origin: Point(
                x: bareScreen.origin.x + margins.left,
                y: bareScreen.origin.y + margins.top
            ),
            size: bareScreen.size
        )
        return DevicePresentation(
            style: .bezel,
            identifier: assets.chrome.identifier,
            formFactor: profile.formFactor,
            viewport: assets.composite.size,
            screen: screen,
            screenScale: profile.screenScale,
            screenCornerRadii: profile.screenCornerRadii
                ?? ScreenCornerRadii(all: assets.chrome.innerCornerRadius),
            nativeOrientation: profile.nativeOrientation,
            bezelPNG: assets.composite.data
        )
    }

    static func frameless(
        profile: DevicePresentationProfile
    ) -> DevicePresentation {
        DevicePresentation(
            style: .frameless,
            identifier: nil,
            formFactor: profile.formFactor,
            viewport: profile.screenSize,
            screen: Rect(
                origin: Point(x: 0, y: 0),
                size: profile.screenSize
            ),
            screenScale: profile.screenScale,
            screenCornerRadii: profile.screenCornerRadii ?? .zero,
            nativeOrientation: profile.nativeOrientation,
            bezelPNG: nil
        )
    }

    var snapshot: DevicePresentationSnapshot {
        var json: [String: Any] = [
            "presentation": style.rawValue,
            "formFactor": formFactor.rawValue,
            "viewport": [
                "width": viewport.width,
                "height": viewport.height,
            ],
            "screen": [
                "x": screen.origin.x,
                "y": screen.origin.y,
                "width": screen.size.width,
                "height": screen.size.height,
                "cornerRadii": screenCornerRadii.json,
            ],
            "screenScale": screenScale,
            "innerCornerRadius": screenCornerRadii.uniformRadius
                ?? max(
                    screenCornerRadii.topLeft,
                    screenCornerRadii.topRight,
                    screenCornerRadii.bottomLeft,
                    screenCornerRadii.bottomRight
                ),
        ]
        if let identifier {
            json["identifier"] = identifier
        }
        if let nativeOrientation {
            json["nativeOrientation"] = nativeOrientation
        }
        let data = try! JSONSerialization.data(
            withJSONObject: json,
            options: [.sortedKeys]
        )
        return DevicePresentationSnapshot(
            layoutJSON: String(decoding: data, as: UTF8.self),
            bezelPNG: bezelPNG
        )
    }
}

public struct DevicePresentationSnapshot: Equatable, Sendable {
    public let layoutJSON: String
    public let bezelPNG: Data?

    init(layoutJSON: String, bezelPNG: Data?) {
        self.layoutJSON = layoutJSON
        self.bezelPNG = bezelPNG
    }
}
