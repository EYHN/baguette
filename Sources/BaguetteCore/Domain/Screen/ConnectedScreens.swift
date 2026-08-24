import Foundation

/// Pure binding heuristic over live framebuffer port snapshots.
/// The device plane is the largest port of the device's own shape;
/// CarPlay is max area among the remaining eligible externals, with
/// ~720×480 as an area tie-break only.
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
        guard let winner = devicePort(in: ports) else {
            throw FramebufferSelectionError.noMatchingPort(.phone)
        }
        return try makeBinding(kind: .phone, port: winner)
    }

    private static func bindCarPlay(ports: [FramebufferPortSnapshot]) throws -> DisplayBinding {
        guard let device = devicePort(in: ports) else {
            throw FramebufferSelectionError.noMatchingPort(.carPlay)
        }
        let externals = ports.filter {
            $0 != device && FramebufferSurfacePick.acceptsExternal($0.size)
        }
        guard let best = pickBestExternal(from: externals) else {
            throw FramebufferSelectionError.noMatchingPort(.carPlay)
        }
        return try makeBinding(kind: .carPlay, port: best)
    }

    /// Which port is the device's own screen.
    ///
    /// Largest area is the usual tell and stays the tie-break, but it
    /// cannot be the whole rule: a 4K external out-measures every phone
    /// ever made, so on `[phone, 4K]` it awarded the device slot to the
    /// external — and the portrait phone left over is not a landscape
    /// external, so the CarPlay plane then reported nothing attached for
    /// a screen the user was looking at. Both planes ended up on the
    /// wrong port from one attach.
    ///
    /// Shape settles it instead. Portrait is the device's own shape and
    /// no display the External Displays menu offers is portrait, so when
    /// any portrait port exists the largest one is the device. With none
    /// — nothing attached but a landscape iPad, say — largest area is
    /// still the best answer available.
    private static func devicePort(
        in ports: [FramebufferPortSnapshot]
    ) -> FramebufferPortSnapshot? {
        let portrait = ports.filter { $0.size.height > $0.size.width }
        let pool = portrait.isEmpty ? ports : portrait
        return pool.max(by: { $0.area < $1.area })
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
