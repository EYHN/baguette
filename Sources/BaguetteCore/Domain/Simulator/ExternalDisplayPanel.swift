import Foundation
import Mockable

/// Host Simulator menu path for I/O → External Displays → CarPlay.
/// Irreducible AppleScript / Accessibility lives in the Infra impl;
/// orchestrators depend on this role noun.
@Mockable
protocol ExternalDisplayPanel: Sendable {
    func enableCarPlay() throws
}
