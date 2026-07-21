import Foundation

/// Live identity of one connected SimulatorKit screen after resolve.
/// Creatable plist ids are not stored — only the connected id observed
/// at resolve time.
struct DisplayBinding: Sendable, Equatable {
    let kind: DisplayKind
    let connectedScreenId: UInt32
    let portName: String
    let size: Size
}

/// Point-in-time port facts lifted from SimulatorKit for pure selection.
struct FramebufferPortSnapshot: Sendable, Equatable {
    let portName: String
    let connectedScreenId: UInt32?
    let size: Size

    var area: Double { size.width * size.height }
}

enum FramebufferSelectionError: Error, Equatable {
    case noMatchingPort(DisplayKind)
    case screenIdUnavailable
}
