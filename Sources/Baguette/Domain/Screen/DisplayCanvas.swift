import Foundation

/// A whole-pixel rectangle on a `DisplayCanvas`.
struct CanvasRect: Equatable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

/// The one plane a foldable streams: every integrated panel at its own
/// raw size, side by side, whether or not it is lit. A stream's size is
/// fixed when it is negotiated, and a foldable would otherwise change it
/// on every fold — and an app may light both panels at once (iOS 27.1's
/// camera capture scene accessory), which no single-panel plane can show.
///
/// Panels are laid out unrotated, in the raw framebuffer frame, like every
/// other plane here; each panel's orientation travels in the layout.
struct DisplayCanvas: Equatable, Sendable {
    struct Region: Equatable, Sendable {
        let panel: DisplayPanel
        let rect: CanvasRect
    }

    let width: Int
    let height: Int
    let regions: [Region]

    /// Nil for a device with one display: it streams that display as is.
    /// `scale` divides each panel (1 = native). Every edge is even, as
    /// I420's half-size chroma planes need.
    static func laying(out panels: DisplayPanels, scale: Int) -> DisplayCanvas? {
        guard panels.isFoldable else { return nil }
        let divisor = max(1, scale)
        var x = 0
        var regions: [Region] = []
        for panel in panels.panels {
            let width = max(2, Int(panel.pixelSize.width) / divisor) & ~1
            let height = max(2, Int(panel.pixelSize.height) / divisor) & ~1
            regions.append(Region(panel: panel, rect: CanvasRect(x: x, y: 0, width: width, height: height)))
            x += width
        }
        return DisplayCanvas(width: x, height: regions.map(\.rect.height).max() ?? 0, regions: regions)
    }

    func region(screenID: UInt32) -> Region? {
        regions.first { $0.panel.screenID == screenID }
    }

    /// The description that travels beside each frame.
    /// `uiOrientationRaw` is SimulatorKit's value, which both panels
    /// report alike; each panel restates it in the phone convention.
    /// `hingeDegrees` is the foldable's hinge, when it is known: the
    /// stream says the angle instead of leaving viewers to guess it
    /// from which panel is lit. Nil on a device that does not fold.
    func layoutJSON(activeScreenID: UInt32?, uiOrientationRaw: Int, hingeDegrees: Double? = nil) -> String {
        var layout: [String: Any] = [
            "canvas": ["width": width, "height": height],
            "panels": regions.map { region -> [String: Any] in
                [
                    "screenId": Int(region.panel.screenID),
                    "x": region.rect.x,
                    "y": region.rect.y,
                    "width": region.rect.width,
                    "height": region.rect.height,
                    "pointWidth": Double(region.panel.pointSize.width),
                    "pointHeight": Double(region.panel.pointSize.height),
                    "active": region.panel.screenID == activeScreenID,
                    "uiOrientation": region.panel.canonicalUIOrientation(uiOrientationRaw),
                ]
            },
        ]
        if let hingeDegrees {
            layout["hinge"] = ["degrees": hingeDegrees]
        }
        let data = try! JSONSerialization.data(withJSONObject: layout, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

/// Tightly packed I420 planes for a `DisplayCanvas`, black until a panel
/// is drawn. Panels are drawn independently, so a static panel costs
/// nothing after its first frame.
struct I420Canvas: Equatable, Sendable {
    let width: Int
    let height: Int
    private(set) var planes: Data

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        let luma = width * height
        let chroma = (width / 2) * (height / 2)
        // Limited-range black: Y 16, U and V 128.
        planes = Data(repeating: 16, count: luma) + Data(repeating: 128, count: 2 * chroma)
    }

    /// Copies one panel's tightly packed I420 planes (`width` × `height`)
    /// into `rect`. Ignored unless the planes are exactly the region's
    /// size and the region lies on the canvas.
    mutating func draw(_ source: Data, width sourceWidth: Int, height sourceHeight: Int, at rect: CanvasRect) {
        let sourceChromaWidth = sourceWidth / 2
        let sourceChromaHeight = sourceHeight / 2
        guard sourceWidth == rect.width, sourceHeight == rect.height,
              rect.x >= 0, rect.y >= 0,
              rect.x + rect.width <= width, rect.y + rect.height <= height,
              source.count == sourceWidth * sourceHeight + 2 * sourceChromaWidth * sourceChromaHeight
        else { return }
        let chromaWidth = width / 2
        let lumaSize = width * height
        let chromaSize = chromaWidth * (height / 2)
        source.withUnsafeBytes { (from: UnsafeRawBufferPointer) in
            planes.withUnsafeMutableBytes { (to: UnsafeMutableRawBufferPointer) in
                guard let from = from.baseAddress, let to = to.baseAddress else { return }
                for row in 0 ..< sourceHeight {
                    memcpy(to + (rect.y + row) * width + rect.x, from + row * sourceWidth, sourceWidth)
                }
                let sourceLuma = sourceWidth * sourceHeight
                let sourceChroma = sourceChromaWidth * sourceChromaHeight
                for plane in 0 ..< 2 {
                    let destination = to + lumaSize + plane * chromaSize
                    let origin = from + sourceLuma + plane * sourceChroma
                    for row in 0 ..< sourceChromaHeight {
                        memcpy(
                            destination + (rect.y / 2 + row) * chromaWidth + rect.x / 2,
                            origin + row * sourceChromaWidth,
                            sourceChromaWidth
                        )
                    }
                }
            }
        }
    }
}
