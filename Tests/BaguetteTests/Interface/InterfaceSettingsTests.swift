import Testing
import Foundation
@testable import BaguetteCore

/// The three settings `xcrun simctl ui <udid> …` exposes — appearance,
/// increase-contrast and content size.
///
/// Each is its own value with a parser for what simctl *prints* and a
/// projection to what simctl *accepts*. Those two alphabets differ:
/// reading content size answers a category name, while setting it also
/// accepts `increment` / `decrement`. Keeping them apart is what stops
/// a read echoing back as an invalid write.
@Suite("Interface settings")
struct InterfaceSettingsTests {

    // MARK: - appearance

    @Test func `appearance parses what simctl prints`() {
        #expect(InterfaceAppearance(output: "light") == .light)
        #expect(InterfaceAppearance(output: "dark") == .dark)
    }

    @Test func `a device that cannot answer is unknown, not a failure`() {
        // A shut-down device answers "unknown" and exits 0 — asked
        // before boot, the honest answer is "I don't know", not an
        // error and certainly not a made-up "light".
        #expect(InterfaceAppearance(output: "unknown") == .unknown)
        #expect(InterfaceAppearance(output: "unsupported") == .unsupported)
    }

    @Test func `appearance tolerates the newline simctl leaves behind`() {
        #expect(InterfaceAppearance(output: "dark\n") == .dark)
        #expect(InterfaceAppearance(output: "  light  ") == .light)
    }

    @Test func `an unrecognised appearance reads as unknown`() {
        #expect(InterfaceAppearance(output: "chartreuse") == .unknown)
        #expect(InterfaceAppearance(output: "") == .unknown)
    }

    @Test func `only a real appearance can be set`() {
        // `unknown` / `unsupported` are answers, never instructions —
        // there's no argv that means "make it unknown".
        #expect(InterfaceAppearance.dark.argument == "dark")
        #expect(InterfaceAppearance.light.argument == "light")
        #expect(InterfaceAppearance.unknown.argument == nil)
        #expect(InterfaceAppearance.unsupported.argument == nil)
    }

    @Test func `appearance can be flipped, which is what a toggle needs`() {
        #expect(InterfaceAppearance.light.toggled == .dark)
        #expect(InterfaceAppearance.dark.toggled == .light)
        // Nothing to flip to when we don't know where we are.
        #expect(InterfaceAppearance.unknown.toggled == nil)
        #expect(InterfaceAppearance.unsupported.toggled == nil)
    }

    // MARK: - increase contrast

    @Test func `contrast parses what simctl prints`() {
        #expect(InterfaceContrast(output: "enabled") == .enabled)
        #expect(InterfaceContrast(output: "disabled\n") == .disabled)
        #expect(InterfaceContrast(output: "unsupported") == .unsupported)
        #expect(InterfaceContrast(output: "nonsense") == .unknown)
    }

    @Test func `only a real contrast setting can be set`() {
        #expect(InterfaceContrast.enabled.argument == "enabled")
        #expect(InterfaceContrast.disabled.argument == "disabled")
        #expect(InterfaceContrast.unknown.argument == nil)
    }

    @Test func `contrast can be flipped`() {
        #expect(InterfaceContrast.enabled.toggled == .disabled)
        #expect(InterfaceContrast.disabled.toggled == .enabled)
        #expect(InterfaceContrast.unknown.toggled == nil)
    }

    // MARK: - content size

    @Test func `content size parses every standard category`() {
        #expect(ContentSize(output: "extra-small") == .extraSmall)
        #expect(ContentSize(output: "small") == .small)
        #expect(ContentSize(output: "medium") == .medium)
        #expect(ContentSize(output: "large") == .large)
        #expect(ContentSize(output: "extra-large") == .extraLarge)
        #expect(ContentSize(output: "extra-extra-large") == .extraExtraLarge)
        #expect(ContentSize(output: "extra-extra-extra-large") == .extraExtraExtraLarge)
    }

    @Test func `content size parses the accessibility range`() {
        // The five accessibility sizes are the whole point of exposing
        // this to an a11y audit — they're where layouts break.
        #expect(ContentSize(output: "accessibility-medium") == .accessibilityMedium)
        #expect(ContentSize(output: "accessibility-large") == .accessibilityLarge)
        #expect(ContentSize(output: "accessibility-extra-large") == .accessibilityExtraLarge)
        #expect(ContentSize(output: "accessibility-extra-extra-large") == .accessibilityExtraExtraLarge)
        #expect(
            ContentSize(output: "accessibility-extra-extra-extra-large")
                == .accessibilityExtraExtraExtraLarge
        )
    }

    @Test func `content size round-trips through its wire name`() {
        // Every real size must project back to the exact token simctl
        // accepts, or setting what we just read would fail.
        for size in ContentSize.settable {
            #expect(ContentSize(output: size.argument ?? "") == size)
        }
    }

    @Test func `an unreadable content size is unknown`() {
        #expect(ContentSize(output: "unknown") == .unknown)
        #expect(ContentSize(output: "unsupported") == .unsupported)
        #expect(ContentSize(output: "gigantic") == .unknown)
    }

    @Test func `the settable sizes are the twelve real ones, in order`() {
        // Ordered smallest → largest so a UI can render them as a scale
        // and step through them.
        #expect(ContentSize.settable.count == 12)
        #expect(ContentSize.settable.first == .extraSmall)
        #expect(ContentSize.settable.last == .accessibilityExtraExtraExtraLarge)
        #expect(!ContentSize.settable.contains(.unknown))
        #expect(!ContentSize.settable.contains(.unsupported))
    }

    @Test func `the accessibility sizes are flagged as such`() {
        #expect(ContentSize.accessibilityLarge.isAccessibilitySize)
        #expect(!ContentSize.large.isAccessibilitySize)
    }

    // MARK: - changing content size

    @Test func `a content-size change speaks simctl's setting alphabet`() {
        // Reading answers a category; setting also accepts relative
        // steps. Two alphabets, so two types.
        #expect(ContentSizeChange.increment.argument == "increment")
        #expect(ContentSizeChange.decrement.argument == "decrement")
        #expect(ContentSizeChange.size(.accessibilityLarge).argument == "accessibility-large")
    }

    @Test func `a content-size change parses from the wire`() {
        #expect(ContentSizeChange(wire: "increment") == .increment)
        #expect(ContentSizeChange(wire: "decrement") == .decrement)
        #expect(ContentSizeChange(wire: "extra-large") == .size(.extraLarge))
        #expect(ContentSizeChange(wire: "unknown") == nil)
        #expect(ContentSizeChange(wire: "nonsense") == nil)
    }

    @Test func `a change wrapping a read-only size names no argument`() {
        // `.size(.unknown)` is constructible in-module, and silently
        // spelling it `large` would set the device to an unrelated
        // category. No argument means the setter refuses instead —
        // matching how appearance and contrast already behave.
        #expect(ContentSizeChange.size(.unknown).argument == nil)
        #expect(ContentSizeChange.size(.unsupported).argument == nil)
    }
}
