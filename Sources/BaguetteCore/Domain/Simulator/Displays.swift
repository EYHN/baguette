import Foundation
import Mockable

/// Plural aggregate hung off Simulator — indexes the simulator's
/// display planes (phone + CarPlay). Does not enable CarPlay itself;
/// that lives on `ExternalDisplays`.
@Mockable
protocol Displays: Sendable {
    var phone: any Display { get }
    var carPlay: any Display { get }
}

extension Displays {
    subscript(_ kind: DisplayKind) -> any Display {
        switch kind {
        case .phone: return phone
        case .carPlay: return carPlay
        }
    }
}
