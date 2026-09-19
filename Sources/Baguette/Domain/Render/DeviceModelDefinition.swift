import Foundation

struct DeviceModelID: RawRepresentable, Equatable, Hashable, Sendable, Codable,
                      ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

struct RenderDimensions: Equatable, Sendable, Codable {
    let width: Int
    let height: Int
}

enum DeviceModelOrientation: String, Equatable, Sendable, Codable {
    case portrait
    case landscape
}

struct DeviceModelMatches: Equatable, Sendable, Codable {
    let simulatorDeviceTypes: [String]
    let deviceNames: [String]
    /// Physical-hardware identifiers (`utsname.machine`, e.g.
    /// "iPhone14,3") for the device-twin path. Optional in the JSON so
    /// every pre-existing definition keeps parsing.
    let deviceModels: [String]

    init(
        simulatorDeviceTypes: [String] = [],
        deviceNames: [String] = [],
        deviceModels: [String] = []
    ) {
        self.simulatorDeviceTypes = simulatorDeviceTypes
        self.deviceNames = deviceNames
        self.deviceModels = deviceModels
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        simulatorDeviceTypes = try container.decodeIfPresent(
            [String].self, forKey: .simulatorDeviceTypes) ?? []
        deviceNames = try container.decodeIfPresent(
            [String].self, forKey: .deviceNames) ?? []
        deviceModels = try container.decodeIfPresent(
            [String].self, forKey: .deviceModels) ?? []
    }
}

struct DeviceModelAsset: Equatable, Sendable, Codable {
    let file: String?
    let downloadURL: String?
    let sha256: String?
    /// An asset Apple ships inside Xcode, named by its path under the
    /// selected Xcode's `Contents/` — iPhone Duo's `V68.usdz` lives in
    /// DeviceKit's plug-in, and is read from there like the 2D chromes
    /// are read from `/Library/Developer/DeviceKit`.
    let xcodeResource: String?

    init(file: String?, downloadURL: String?, sha256: String?, xcodeResource: String? = nil) {
        self.file = file
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.xcodeResource = xcodeResource
    }
}

/// A foldable's book, as its model animates it. The clip shuts the book
/// from flat at its start to shut at `shutTime`; the cover is the
/// screen on the far side of the leaf that folds over.
struct DeviceModelFold: Equatable, Sendable, Codable {
    let clip: String
    let shutTime: Double
    let coverMaterial: String
    let coverTextureSize: RenderDimensions
    /// Quarter turns (degrees, clockwise) the cover's frames need to
    /// read upright on the mesh; nil is none.
    let coverTextureRotation: Int?
    /// The hinge angle of Device Hub's open pose: from here up the bend
    /// is centred between the halves.
    let openPoseDegrees: Double

    init(
        clip: String,
        shutTime: Double,
        coverMaterial: String,
        coverTextureSize: RenderDimensions,
        coverTextureRotation: Int? = nil,
        openPoseDegrees: Double
    ) {
        self.clip = clip
        self.shutTime = shutTime
        self.coverMaterial = coverMaterial
        self.coverTextureSize = coverTextureSize
        self.coverTextureRotation = coverTextureRotation
        self.openPoseDegrees = openPoseDegrees
    }
}

struct DeviceModelScene: Equatable, Sendable, Codable {
    let rootNode: String
    let screenNode: String?
    let screenMaterial: String
    let nativeOrientation: DeviceModelOrientation
    let textureSize: RenderDimensions
    let usesScreenOverlay: Bool
    /// Quarter turns (degrees, clockwise) the screen's frames need to
    /// read upright on the mesh, when its UVs run the other way from the
    /// framebuffer; nil is none.
    let textureRotation: Int?
    /// Turns an asset authored lying flat (screen up) to face the
    /// camera before any requested rotation; nil for models authored
    /// standing up.
    let restRotation: DeviceRotation?
    let fold: DeviceModelFold?

    init(
        rootNode: String,
        screenNode: String?,
        screenMaterial: String,
        nativeOrientation: DeviceModelOrientation,
        textureSize: RenderDimensions,
        usesScreenOverlay: Bool,
        textureRotation: Int? = nil,
        restRotation: DeviceRotation? = nil,
        fold: DeviceModelFold? = nil
    ) {
        self.rootNode = rootNode
        self.screenNode = screenNode
        self.screenMaterial = screenMaterial
        self.nativeOrientation = nativeOrientation
        self.textureSize = textureSize
        self.usesScreenOverlay = usesScreenOverlay
        self.textureRotation = textureRotation
        self.restRotation = restRotation
        self.fold = fold
    }
}

struct DeviceVariantChoice: Equatable, Sendable, Codable {
    let id: String
    let displayName: String
    let usdValue: String
    let previewColor: String?
    let materialColors: [String: String]?

    init(
        id: String,
        displayName: String,
        usdValue: String,
        previewColor: String?,
        materialColors: [String: String]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.usdValue = usdValue
        self.previewColor = previewColor
        self.materialColors = materialColors
    }
}

enum DeviceVariantKind: String, Equatable, Sendable, Codable {
    case usd
    case materials
}

struct DeviceVariantSet: Equatable, Sendable, Codable {
    let id: String
    let displayName: String
    let primPath: String
    let usdName: String
    let `default`: String
    let choices: [DeviceVariantChoice]
    let kind: DeviceVariantKind?

    init(
        id: String,
        displayName: String,
        primPath: String,
        usdName: String,
        default: String,
        choices: [DeviceVariantChoice],
        kind: DeviceVariantKind? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.primPath = primPath
        self.usdName = usdName
        self.default = `default`
        self.choices = choices
        self.kind = kind
    }
}

struct DeviceVariantSelection: Equatable, Sendable {
    let setID: String
    let primPath: String
    let usdName: String
    let usdValue: String
    let materialColors: [String: String]
    let kind: DeviceVariantKind

    init(
        setID: String,
        primPath: String,
        usdName: String,
        usdValue: String,
        materialColors: [String: String] = [:],
        kind: DeviceVariantKind = .usd
    ) {
        self.setID = setID
        self.primPath = primPath
        self.usdName = usdName
        self.usdValue = usdValue
        self.materialColors = materialColors
        self.kind = kind
    }
}

struct DeviceModelDefinition: Equatable, Sendable, Codable {
    let schemaVersion: Int
    let id: DeviceModelID
    let displayName: String
    let matches: DeviceModelMatches
    let asset: DeviceModelAsset
    let scene: DeviceModelScene
    let variantSets: [DeviceVariantSet]

    static func parsing(json: Data) throws -> DeviceModelDefinition {
        let definition: DeviceModelDefinition
        do {
            definition = try JSONDecoder().decode(DeviceModelDefinition.self, from: json)
        } catch {
            throw DeviceModelError.malformedJSON
        }
        try definition.validate()
        return definition
    }

    func matches(deviceType: String, deviceName: String) -> Bool {
        matches.simulatorDeviceTypes.contains(deviceType)
            || matches.deviceNames.contains(deviceName)
    }

    /// Match a physical device by its hardware identifier — the
    /// device-twin sibling of `matches(deviceType:deviceName:)`.
    func matches(hardware: String) -> Bool {
        matches.deviceModels.contains(hardware)
    }

    func resolveVariants(_ requested: [String: String]) throws -> [DeviceVariantSelection] {
        let knownSets = Set(variantSets.map(\.id))
        if let unknown = requested.keys.sorted().first(where: { !knownSets.contains($0) }) {
            throw DeviceModelError.unknownVariantSet(unknown)
        }

        return try variantSets.map { set in
            let choiceID = requested[set.id] ?? set.default
            guard let choice = set.choices.first(where: { $0.id == choiceID }) else {
                throw DeviceModelError.unknownVariantChoice(
                    set: set.id,
                    choice: choiceID,
                    allowed: set.choices.map(\.id)
                )
            }
            return DeviceVariantSelection(
                setID: set.id,
                primPath: set.primPath,
                usdName: set.usdName,
                usdValue: choice.usdValue,
                materialColors: choice.materialColors ?? [:],
                kind: set.kind ?? .usd
            )
        }
    }

    private func validate() throws {
        guard schemaVersion == 1 else {
            throw DeviceModelError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !id.rawValue.isEmpty else {
            throw DeviceModelError.emptyField("id")
        }
        guard !displayName.isEmpty else {
            throw DeviceModelError.emptyField("displayName")
        }
        guard scene.textureSize.width > 0, scene.textureSize.height > 0 else {
            throw DeviceModelError.invalidTextureSize
        }
        guard asset.file?.isEmpty == false || asset.downloadURL?.isEmpty == false
                || asset.xcodeResource?.isEmpty == false else {
            throw DeviceModelError.missingAsset
        }
        for turn in [scene.textureRotation, scene.fold?.coverTextureRotation].compactMap({ $0 }) {
            guard turn % 90 == 0 else { throw DeviceModelError.invalidTextureRotation(turn) }
        }
        if let fold = scene.fold {
            guard !fold.clip.isEmpty else { throw DeviceModelError.emptyField("scene.fold.clip") }
            guard fold.shutTime > 0, fold.openPoseDegrees > 0, fold.openPoseDegrees <= 180,
                  fold.coverTextureSize.width > 0, fold.coverTextureSize.height > 0,
                  !fold.coverMaterial.isEmpty else {
                throw DeviceModelError.invalidFold
            }
        }
        if asset.downloadURL?.isEmpty == false {
            guard let hash = asset.sha256,
                  hash.count == 64,
                  hash.allSatisfy({ $0.isHexDigit }) else {
                throw DeviceModelError.downloadRequiresSHA256
            }
        }

        var setIDs = Set<String>()
        for set in variantSets {
            guard setIDs.insert(set.id).inserted else {
                throw DeviceModelError.duplicateVariantSet(set.id)
            }
            guard !set.id.isEmpty, !set.primPath.isEmpty, !set.usdName.isEmpty else {
                throw DeviceModelError.emptyField("variantSets")
            }
            var choiceIDs = Set<String>()
            for choice in set.choices {
                guard choiceIDs.insert(choice.id).inserted else {
                    throw DeviceModelError.duplicateVariantChoice(set: set.id, choice: choice.id)
                }
                for (material, color) in choice.materialColors ?? [:] {
                    guard !material.isEmpty,
                          color.count == 7,
                          color.first == "#",
                          color.dropFirst().allSatisfy(\.isHexDigit) else {
                        throw DeviceModelError.invalidMaterialColor(
                            material: material,
                            color: color
                        )
                    }
                }
            }
            guard choiceIDs.contains(set.default) else {
                throw DeviceModelError.invalidVariantDefault(set: set.id, choice: set.default)
            }
        }
    }
}

enum DeviceModelError: Error, Equatable {
    case malformedJSON
    case unsupportedSchemaVersion(Int)
    case emptyField(String)
    case invalidTextureSize
    case invalidFold
    case invalidTextureRotation(Int)
    case missingAsset
    case downloadRequiresSHA256
    case duplicateVariantSet(String)
    case duplicateVariantChoice(set: String, choice: String)
    case duplicateModelID(String)
    case ambiguousMatch([String])
    case malformedDefinition(String)
    case assetOutsideBundle(String)
    case localAssetNotFound(String)
    case invalidOutputSize
    case invalidRotation
    case invalidUSDIdentifier(String)
    case invalidAssetReference
    case invalidBackground(String)
    case sceneLoadFailed(String)
    case sceneNodeNotFound(String)
    case sceneHasNoGeometry
    case screenImageInvalid
    case renderFailed
    case invalidRotationArgument(String)
    case invalidSizeArgument(String)
    case invalidVariantArgument(String)
    case duplicateVariantSelection(String)
    case modelNotFound(String)
    case noModelForDevice(String)
    case invalidRenderOptions
    case invalidDownloadURL(String)
    case assetDownloadFailed(String)
    case assetHashMismatch
    case assetCacheWriteFailed(String)
    case invalidMaterialColor(material: String, color: String)
    case invalidVariantDefault(set: String, choice: String)
    case unknownVariantSet(String)
    case unknownVariantChoice(set: String, choice: String, allowed: [String])
}
