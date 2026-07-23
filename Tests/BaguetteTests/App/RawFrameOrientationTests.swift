@testable import BaguetteCore
import Foundation
import Testing

@Suite("Raw frame orientation")
struct RawFrameOrientationTests {
    @Test func `maps SimulatorKit UI orientation raw values without geometry guesses`() {
        #expect(ScreenOrientation(simulatorKitRawValue: 1) == .portrait)
        #expect(ScreenOrientation(simulatorKitRawValue: 2) == .portraitUpsideDown)
        #expect(ScreenOrientation(simulatorKitRawValue: 3) == .landscapeRight)
        #expect(ScreenOrientation(simulatorKitRawValue: 4) == .landscapeLeft)
        #expect(ScreenOrientation(simulatorKitRawValue: 0) == nil)
        #expect(ScreenOrientation(simulatorKitRawValue: 5) == nil)
    }

    @Test func `property change updates idle replay without replacing cached pixels`() {
        var cache = RawFramePayloadCache()
        let planes = Data([16, 16, 16, 16, 128, 128])
        cache.store(width: 2, height: 2, planes: planes)

        var emissions: [(orientation: UInt32, planes: Data)] = []
        cache.withPayload(captureMicros: 1) { payload in
            emissions.append((
                orientation: payload.uiOrientationRaw,
                planes: Data(payload.planes)
            ))
        }

        cache.update(metadata: ScreenMetadata(uiOrientation: .landscapeRight))
        cache.withPayload(captureMicros: 2) { payload in
            emissions.append((
                orientation: payload.uiOrientationRaw,
                planes: Data(payload.planes)
            ))
        }

        #expect(emissions.map(\.orientation) == [0, 3])
        #expect(emissions.map(\.planes) == [planes, planes])
    }
}
