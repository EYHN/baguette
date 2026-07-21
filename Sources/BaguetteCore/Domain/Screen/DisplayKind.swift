import Foundation

/// Which framebuffer plane the caller wants. Parsed at App/CLI only.
/// Wire strings: "phone" | "carplay" (case-insensitive). Unknown → nil.
enum DisplayKind: String, Sendable, Equatable {
    case phone
    case carPlay

    static func parse(query: String?) -> DisplayKind? {
        parse(token: query)
    }

    static func parse(cliFlag: String?) -> DisplayKind? {
        parse(token: cliFlag)
    }

    private static func parse(token: String?) -> DisplayKind? {
        guard let token, !token.isEmpty else { return nil }
        switch token.lowercased() {
        case "phone": return .phone
        case "carplay": return .carPlay
        default: return nil
        }
    }
}
