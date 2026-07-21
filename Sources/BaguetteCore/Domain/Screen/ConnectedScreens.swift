import Foundation

/// Pure binding heuristic over live framebuffer port snapshots.
/// Phone is largest area; CarPlay is max area among remaining ports
/// after excluding the phone winner, with ~720×480 as area tie-break only.
enum ConnectedScreens {
    /// Plist CarPlay profile size — documentation / tie-break only.
    /// Runtime IOSurface dims win when areas differ.
    static let carPlayPlistSize = Size(width: 720, height: 480)

    static func binding(
        kind: DisplayKind,
        ports: [FramebufferPortSnapshot]
    ) throws -> DisplayBinding {
        switch kind {
        case .phone:
            return try bindPhone(ports: ports)
        case .carPlay:
            return try bindCarPlay(ports: ports)
        }
    }

    private static func bindPhone(ports: [FramebufferPortSnapshot]) throws -> DisplayBinding {
        guard let winner = ports.max(by: { $0.area < $1.area }) else {
            throw FramebufferSelectionError.noMatchingPort(.phone)
        }
        return try makeBinding(kind: .phone, port: winner)
    }

    private static func bindCarPlay(ports: [FramebufferPortSnapshot]) throws -> DisplayBinding {
        guard let phoneWinner = ports.max(by: { $0.area < $1.area }) else {
            throw FramebufferSelectionError.noMatchingPort(.carPlay)
        }
        let externals = ports.filter {
            $0 != phoneWinner && FramebufferSurfacePick.acceptsCarPlay($0.size)
        }
        guard let best = pickBestExternal(from: externals) else {
            throw FramebufferSelectionError.noMatchingPort(.carPlay)
        }
        return try makeBinding(kind: .carPlay, port: best)
    }

    private static func pickBestExternal(
        from ports: [FramebufferPortSnapshot]
    ) -> FramebufferPortSnapshot? {
        ports.max { a, b in
            if a.area != b.area { return a.area < b.area }
            return distanceToCarPlayPlist(a) > distanceToCarPlayPlist(b)
        }
    }

    private static func distanceToCarPlayPlist(_ port: FramebufferPortSnapshot) -> Double {
        let dw = port.size.width - carPlayPlistSize.width
        let dh = port.size.height - carPlayPlistSize.height
        return dw * dw + dh * dh
    }

    private static func makeBinding(
        kind: DisplayKind,
        port: FramebufferPortSnapshot
    ) throws -> DisplayBinding {
        guard let screenId = port.connectedScreenId else {
            throw FramebufferSelectionError.screenIdUnavailable
        }
        return DisplayBinding(
            kind: kind,
            connectedScreenId: screenId,
            portName: port.portName,
            size: port.size
        )
    }
}
