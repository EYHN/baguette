import CoreGraphics
import Foundation

/// One display built into a device, from the `displays` array of its
/// device type's capabilities. A phone has one; a foldable (iPhone Duo)
/// has two and presents on one at a time.
struct DisplayPanel: Equatable, Sendable {
    let screenID: UInt32
    let pixelSize: CGSize
    let scale: Double
    /// How the panel is mounted relative to the framebuffer it scans
    /// out, in degrees. Duo's inner panel is 270; everything else is 0.
    let nativeRotation: Int

    var pointSize: CGSize {
        CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
    }

    /// SimulatorKit's `uiOrientation` for this panel, restated in the
    /// convention consumers apply (see `ScreenOrientation.canonicalRaw`).
    /// Every foldable needs an Xcode that reports its landscapes swapped,
    /// on the cover panel as much as the inner one — measured against the
    /// picture on both panels of iPhone Duo.
    func canonicalUIOrientation(_ raw: Int) -> Int {
        ScreenOrientation.canonicalRaw(raw, xcodeMajor: 27)
    }
}

/// A device type's built-in, touchable displays, in capabilities order —
/// the first is the one a single-display device would have.
struct DisplayPanels: Equatable, Sendable {
    let panels: [DisplayPanel]

    var isFoldable: Bool { panels.count > 1 }
    var main: DisplayPanel? { panels.first }

    func panel(screenID: UInt32) -> DisplayPanel? {
        panels.first { $0.screenID == screenID }
    }

    /// The panel by the name Connected Screens gives it: the first in
    /// capabilities order is `primary` (a foldable's cover), the next is
    /// `primary-1` (its unfolded panel). Nil for a panel not of this
    /// device.
    func integratedPanel(_ panel: DisplayPanel) -> IntegratedPanel? {
        guard let index = panels.firstIndex(of: panel) else { return nil }
        return index == 0 ? .primary : .secondary
    }

    /// The reverse: nil when the device has no such panel.
    func panel(_ integrated: IntegratedPanel) -> DisplayPanel? {
        switch integrated {
        case .primary: return panels.first
        case .secondary: return panels.count > 1 ? panels[1] : nil
        }
    }

    /// The Indigo target of a panel's digitizer: `0x40000000 | screenID`.
    /// SimulatorHID creates one digitizer per integrated display under
    /// exactly that id (`createDigitizerForTargetID:withDisplayUID:`), so
    /// it names the panel whatever else is going on. The phone constant
    /// does not: on a foldable it lands on whichever digitizer the guest
    /// treats as its main one, and that was the inner panel's on a boot
    /// where the cover panel was presenting — touches were accepted and
    /// delivered to nobody.
    func touchTarget(for panel: DisplayPanel) -> UInt32 {
        0x4000_0000 | panel.screenID
    }

    /// Parses `SimDeviceType.capabilities`.
    static func parsing(_ capabilities: [String: Any]?) -> DisplayPanels {
        let root = capabilities?["capabilities"] as? [String: Any] ?? capabilities
        let displays = root?["displays"] as? [[String: Any]] ?? []
        return DisplayPanels(panels: displays.compactMap { display in
            guard display["displayType"] as? String == "integrated",
                  (display["hasDigitizer"] as? NSNumber)?.boolValue == true,
                  let screenID = (display["screenID"] as? NSNumber)?.uint32Value,
                  let width = (display["width"] as? NSNumber)?.doubleValue,
                  let height = (display["height"] as? NSNumber)?.doubleValue,
                  width > 0, height > 0
            else { return nil }
            let scale = (display["scale"] as? NSNumber)?.doubleValue ?? 1
            return DisplayPanel(
                screenID: screenID,
                pixelSize: CGSize(width: width, height: height),
                scale: scale > 0 ? scale : 1,
                nativeRotation: (display["nativeRotation"] as? NSNumber)?.intValue ?? 0
            )
        })
    }
}

/// Core Device's answer to "which display is this device presenting on",
/// as `devicectl device info displays --json-output -` prints it. Only a
/// device with more than one integrated display reports `active` at all.
enum ActiveDisplayReport {
    static func activeScreenID(in json: Data) -> UInt32? {
        guard let document = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let result = document["result"] as? [String: Any],
              let displays = result["displays"] as? [[String: Any]]
        else { return nil }
        // Usually one. An app may light the cover display as well while
        // the device is unfolded; the single plane stays on the larger
        // panel, which is the one being worked on.
        func area(_ display: [String: Any]) -> Double {
            let size = (display["nativeSize"] as? [NSNumber])?.map(\.doubleValue) ?? []
            return size.count == 2 ? size[0] * size[1] : 0
        }
        let active = displays
            .filter { ($0["active"] as? NSNumber)?.boolValue == true }
            .max { area($0) < area($1) }
        return (active?["displayId"] as? NSNumber)?.uint32Value
    }
}

/// The panel an input line is meant for. A line may carry
/// `"display": <screen id>`; one that does not is for whichever panel the
/// device is presenting on.
enum DisplayAddress {
    static func screenID(in line: String) -> UInt32? {
        // Almost every line names nothing, and a touch stream sends hundreds
        // a second: skip the parse unless the key could be there.
        guard line.contains("\"display\""),
              let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let number = object["display"] as? NSNumber,
              !(object["display"] is String),
              number.doubleValue >= 0, number.doubleValue == number.doubleValue.rounded()
        else { return nil }
        return UInt32(exactly: number.int64Value)
    }
}

extension DisplayAddress {
    /// Dispatches `line`, addressed to the display it names when it names
    /// one. An unknown display is an error, not a touch somewhere else.
    static func dispatch(_ line: String, to input: any Input, through dispatcher: GestureDispatcher) -> String {
        guard let screenID = screenID(in: line) else { return dispatcher.dispatch(line: line) }
        guard let addressable = input as? any DisplayAddressable,
              let ack = addressable.addressing(screenID: screenID, { dispatcher.dispatch(line: line) })
        else { return #"{"ok":false,"error":"unknown display \#(screenID)"}"# }
        return ack
    }
}

/// An input that can aim touches at one panel of a multi-display device.
protocol DisplayAddressable {
    func addressing<T>(screenID: UInt32, _ body: () -> T) -> T?
}
