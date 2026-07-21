import ArgumentParser
import Foundation
import ImageIO

struct Render3DCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "render-3d",
        abstract: "Render a simulator screen on an installed 3D device model"
    )

    @Option(help: "Simulator UDID to capture")
    var udid: String?

    @Option(help: "Existing PNG or JPEG screen image")
    var screen: String?

    @Option(help: "Installed 3D model definition ID")
    var device: String?

    @Option(help: "Custom CoreSimulator device-set path")
    var deviceSet: String?

    @Option(name: .customLong("variant"), help: "Model variant as SET=CHOICE (repeatable)")
    var variants: [String] = []

    @Option(help: "Device rotation as X,Y,Z degrees")
    var rotation: String = "0,0,0"

    @Option(help: "Output dimensions as WIDTHxHEIGHT (defaults to screen size)")
    var size: String?

    @Option(help: "Screen placement: cover, contain, or stretch")
    var fit: String = "cover"

    @Option(help: "Canvas background: transparent or #RRGGBB")
    var background: String = "transparent"

    @Flag(name: .customLong("screen-glass"),
          help: "Composite a reflective cover glass over the screen")
    var screenGlass: Bool = false

    @Option(name: .shortAndLong, help: "Output PNG file (defaults to stdout)")
    var output: String?

    mutating func validate() throws {
        guard (udid == nil) != (screen == nil) else {
            throw ValidationError("exactly one of --udid and --screen is required")
        }
        if screen != nil, device == nil {
            throw ValidationError("--device is required with --screen")
        }
        _ = try DeviceRenderArguments.rotation(rotation)
        if let size { _ = try DeviceRenderArguments.size(size) }
        _ = try DeviceRenderArguments.variants(variants)
        guard DeviceScreenFit(rawValue: fit) != nil else {
            throw ValidationError("--fit must be cover, contain, or stretch")
        }
        if background != "transparent" {
            let pattern = #"^#[0-9A-Fa-f]{6}$"#
            guard background.range(of: pattern, options: .regularExpression) != nil else {
                throw ValidationError("--background must be transparent or #RRGGBB")
            }
        }
    }

    func run() async throws {
        let models = try LiveDeviceModels(rootURLs: DeviceModelRoots.standard())
        let renderer = RealityKitDeviceRenderer()
        let screenImage: Data
        let installed: InstalledDeviceModel

        if let screen {
            screenImage = try Data(contentsOf: URL(fileURLWithPath: screen))
            guard let device,
                  let found = try models.find(id: DeviceModelID(device)) else {
                throw DeviceModelError.modelNotFound(device ?? "")
            }
            installed = found
        } else if let udid {
            let simulators = CoreSimulators(deviceSetPath: deviceSet)
            guard let simulator = simulators.find(udid: udid) else {
                throw SimulatorError.notFound(udid: udid)
            }
            if let device {
                guard let found = try models.find(id: DeviceModelID(device)) else {
                    throw DeviceModelError.modelNotFound(device)
                }
                installed = found
            } else {
                guard let found = try simulator.deviceModel(in: models) else {
                    throw DeviceModelError.noModelForDevice(simulator.deviceTypeName)
                }
                installed = found
            }
            screenImage = try await ScreenSnapshot.capture(
                screen: simulator.screen(),
                quality: 0.95
            )
        } else {
            throw ValidationError("exactly one of --udid and --screen is required")
        }

        let outputSize = try size.map(DeviceRenderArguments.size)
            ?? Self.pixelSize(of: screenImage)
        let plan = try DeviceRenderPlan.build(
            model: installed,
            variants: DeviceRenderArguments.variants(variants),
            rotation: DeviceRenderArguments.rotation(rotation),
            outputSize: outputSize,
            fit: DeviceScreenFit(rawValue: fit) ?? .cover,
            background: background == "transparent"
                ? .transparent
                : .color(background),
            screenGlass: screenGlass
        )
        let png = try renderer.render(plan: plan, screenImage: screenImage)
        if let output {
            try png.write(to: URL(fileURLWithPath: output), options: .atomic)
        } else {
            try FileHandle.standardOutput.write(contentsOf: png)
        }
    }

    private static func pixelSize(of image: Data) throws -> RenderDimensions {
        guard let source = CGImageSourceCreateWithData(image as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source, 0, nil
              ) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw DeviceModelError.screenImageInvalid
        }
        return RenderDimensions(width: width, height: height)
    }
}
