import Foundation

final class LiveDevicePresentations: @unchecked Sendable {
    private let store: any ChromeStore
    private let chromes: LiveChromes

    init(store: any ChromeStore, rasterizer: any PDFRasterizer) {
        self.store = store
        chromes = LiveChromes(store: store, rasterizer: rasterizer)
    }

    func presentation(forDeviceName deviceName: String) throws -> DevicePresentation {
        let profileData = try store.profilePlistData(deviceName: deviceName)
        let capabilitiesData = try? store.capabilitiesPlistData(
            deviceName: deviceName
        )
        let profile = try DevicePresentationProfile.parsing(
            plistData: profileData,
            capabilitiesData: capabilitiesData,
            deviceName: deviceName
        )
        guard let chromeIdentifier = profile.chromeIdentifier else {
            return .frameless(profile: profile)
        }
        guard let assets = chromes.assets(
            chromeIdentifier: chromeIdentifier,
            screenSize: profile.screenSize
        ) else {
            if profile.chromeIsOptional {
                return .frameless(profile: profile)
            }
            throw DevicePresentationResolveError.chromeUnavailable(
                chromeIdentifier
            )
        }
        return .framed(profile: profile, assets: assets)
    }
}
