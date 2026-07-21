import Foundation
import Mockable

/// Host I/O panel that creates/attaches the CarPlay external display.
/// Domain noun for "External Displays" in the Simulator menu — not a
/// Manager/Service/Port. AppleScript / Accessibility live in Infra.
@Mockable
protocol ExternalDisplays: Sendable {
    /// Idempotent: I/O → External Displays → CarPlay. No-op if already on.
    func enableCarPlay() throws

    /// True when a CarPlay external display is connected (live probe).
    var isCarPlayConnected: Bool { get }
}
