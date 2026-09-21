import Foundation

/// SimulatorKit's authoritative UI orientation for a display.
///
/// These raw values come from `screenProperties.uiOrientation` on the
/// framebuffer port's descriptor; they are not inferred from framebuffer
/// dimensions, which are ambiguous during rotation.
enum ScreenOrientation: UInt32, Sendable {
    case portrait = 1
    case portraitUpsideDown = 2
    case landscapeRight = 3
    case landscapeLeft = 4
}
