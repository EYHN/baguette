import Foundation

/// Picks which live framebuffer surface to emit for a display binding.
/// CarPlay never falls back to a phone-sized plane — better to emit
/// nothing than to mirror SpringBoard into the CarPlay pane.
enum FramebufferSurfacePick {
    /// Soft upper bound: CarPlay-ish surfaces stay well under a phone panel.
    private static let maxCarPlayArea = 800.0 * 480.0 * 4.0
    private static let minCarPlayArea = 50_000.0

    static func index(
        binding: DisplayBinding?,
        candidates: [Size]
    ) -> Int? {
        guard !candidates.isEmpty else { return nil }
        guard let binding else {
            return candidates.indices.max { candidates[$0].area < candidates[$1].area }
        }
        switch binding.kind {
        case .phone:
            return closestIndex(to: binding.size, in: candidates)
        case .carPlay:
            let eligible = candidates.indices.filter { acceptsCarPlay(candidates[$0]) }
            guard !eligible.isEmpty else { return nil }
            return eligible.min { a, b in
                distance(candidates[a], binding.size) < distance(candidates[b], binding.size)
            }
        }
    }

    static func acceptsCarPlay(_ size: Size) -> Bool {
        size.width >= size.height
            && size.area >= minCarPlayArea
            && size.area <= maxCarPlayArea
    }

    private static func closestIndex(to target: Size, in candidates: [Size]) -> Int? {
        candidates.indices.min {
            distance(candidates[$0], target) < distance(candidates[$1], target)
        }
    }

    private static func distance(_ a: Size, _ b: Size) -> Double {
        let dw = a.width - b.width
        let dh = a.height - b.height
        return dw * dw + dh * dh
    }
}

private extension Size {
    var area: Double { width * height }
}
