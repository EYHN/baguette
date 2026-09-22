import CoreGraphics
import Foundation
import Testing
@testable import BaguetteCore

@Suite("DisplayCanvas")
struct DisplayCanvasTests {
    private func duo() -> DisplayCanvas {
        let panels = DisplayPanels(panels: [
            DisplayPanel(screenID: 1, pixelSize: CGSize(width: 100, height: 200), scale: 2, nativeRotation: 0),
            DisplayPanel(screenID: 3, pixelSize: CGSize(width: 200, height: 300), scale: 2, nativeRotation: 270),
        ])
        return try! #require(DisplayCanvas.laying(out: panels, scale: 1))
    }

    @Test func `the layout names the hinge when one is known`() throws {
        let json = duo().layoutJSON(activeScreenID: 3, uiOrientationRaw: 1, hingeDegrees: 130)
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let hinge = object?["hinge"] as? [String: Any]
        #expect(hinge?["degrees"] as? Double == 130)
        let panels = object?["panels"] as? [[String: Any]]
        #expect(panels?.count == 2)
        #expect(panels?.last?["active"] as? Bool == true)
    }

    @Test func `a layout without a hinge reading omits it`() throws {
        let json = duo().layoutJSON(activeScreenID: 1, uiOrientationRaw: 1)
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        #expect(object?["hinge"] == nil)
    }
}
