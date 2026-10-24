import Foundation

struct DeviceRotation: Equatable, Sendable, Codable {
    let x: Double
    let y: Double
    let z: Double

    static let zero = DeviceRotation(x: 0, y: 0, z: 0)
}

enum ScreenRotation: Int, CaseIterable, Sendable {
    case none = 0
    case quarter = 90
    case half = 180
    case threeQuarters = 270

    var swapsDimensions: Bool { self == .quarter || self == .threeQuarters }

    /// The counterclockwise turn from an upright capture taken in
    /// `orientation` back to its panel's own buffer: a quarter turn per
    /// step of the interface cycle from portrait, on either panel.
    init(capturedIn orientation: DeviceOrientation?) {
        switch orientation {
        case .landscapeLeft?: self = .quarter
        case .portraitUpsideDown?: self = .half
        case .landscapeRight?: self = .threeQuarters
        case .portrait?, nil: self = .none
        }
    }
}

enum DeviceScreenFit: String, Equatable, Sendable, Codable {
    case cover
    case contain
    case stretch
}

enum DeviceRenderBackground: Equatable, Sendable {
    case transparent
    case color(String)
}

struct DeviceRenderPlan: Equatable, Sendable {
    let model: InstalledDeviceModel
    let variants: [DeviceVariantSelection]
    let rotation: DeviceRotation
    let outputSize: RenderDimensions
    let fit: DeviceScreenFit
    let background: DeviceRenderBackground
    /// Composite a reflective cover-glass layer over the screen. Off by
    /// default so automation screenshots stay pixel-stable.
    let screenGlass: Bool
    let hingeDegrees: Double?
    /// The interface orientation a saved capture was taken in. With it the
    /// image turns back to its panel's buffer and `rotation` includes the
    /// roll that stands the capture upright; without it neither happens.
    let screenOrientation: DeviceOrientation?

    var screenPanel: IntegratedPanel? {
        hingeDegrees.map(Self.posedPanel(hingeDegrees:))
    }

    /// The panel a still render lights at `hingeDegrees`. A saved capture
    /// has no device to ask, so the pose is drawn the way the runtime
    /// settles a slow sweep: the cover below 90°, the unfolded panel from
    /// there on. A live device's lit panel is Core Device's answer
    /// (`Simulator.litPanel()`), never this.
    static func posedPanel(hingeDegrees: Double) -> IntegratedPanel {
        hingeDegrees >= 90 ? .secondary : .primary
    }

    var screenRotation: ScreenRotation {
        ScreenRotation(capturedIn: screenOrientation)
    }

    /// The glass layer is shaped for the inner screen and is left out when
    /// a pose lights the cover, where it would float beside the shut book.
    var rendersScreenGlass: Bool {
        screenGlass && screenPanel != .primary
    }

    static func build(
        model: InstalledDeviceModel,
        variants: [String: String],
        rotation: DeviceRotation,
        outputSize: RenderDimensions,
        fit: DeviceScreenFit = .cover,
        background: DeviceRenderBackground = .transparent,
        screenGlass: Bool = false,
        hingeDegrees: Double? = nil,
        screenOrientation: DeviceOrientation? = nil
    ) throws -> DeviceRenderPlan {
        guard outputSize.width > 0, outputSize.height > 0 else {
            throw DeviceModelError.invalidOutputSize
        }
        guard rotation.x.isFinite, rotation.y.isFinite, rotation.z.isFinite else {
            throw DeviceModelError.invalidRotation
        }
        if let hingeDegrees {
            guard model.definition.scene.fold != nil else {
                throw DeviceModelError.modelCannotFold(model.definition.id.rawValue)
            }
            guard hingeDegrees.isFinite, (0...180).contains(hingeDegrees) else {
                throw DeviceModelError.invalidHingeAngle
            }
        }
        if case .color(let color) = background {
            let pattern = #"^#[0-9A-Fa-f]{6}$"#
            guard color.range(of: pattern, options: .regularExpression) != nil else {
                throw DeviceModelError.invalidBackground(color)
            }
        }
        // A foldable left at its rest pose lies flat, its inner screen lit;
        // a phone's one panel turns like a cover.
        let litPanel = model.definition.scene.fold == nil
            ? IntegratedPanel.primary
            : posedPanel(hingeDegrees: hingeDegrees ?? 180)
        let roll = screenOrientation.map { InterfaceRoll.degrees($0, litPanel: litPanel) } ?? 0
        return DeviceRenderPlan(
            model: model,
            variants: try model.definition.resolveVariants(variants),
            rotation: DeviceRotation(x: rotation.x, y: rotation.y, z: rotation.z + roll),
            outputSize: outputSize,
            fit: fit,
            background: background,
            screenGlass: screenGlass,
            hingeDegrees: hingeDegrees,
            screenOrientation: screenOrientation
        )
    }
}
