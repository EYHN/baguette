import Foundation
import ObjectiveC
import CoreGraphics
import Darwin

/// KVC + ObjC-runtime helpers for reading standard
/// `AXPMacPlatformElement` properties off any `NSObject`.
///
/// Lives in Domain (not Infrastructure) because it talks only to
/// the public ObjC runtime — it doesn't know about
/// `AXPTranslator`, `AXPMacPlatformElement`, or any private
/// framework symbol. That makes the walk-tree-into-`AXNode`
/// logic a pure function the `AXPTranslatorAccessibility`
/// adapter can drive once it's pulled the root element back from
/// the AX XPC round-trip.
///
/// Tests cover this through `AXNode.walk(...)` against
/// `FakeAXTreeElement` `NSObject` subclasses that override the
/// same selectors / KVC keys the production element responds to.
enum AXElementReader {
    /// Device + app process generation + native 64-bit object identity.
    /// Never derive this from labels, values, geometry, or tree positions.
    static func nodeID(_ obj: NSObject, device: String?) -> String? {
        guard let device, let uuid = UUID(uuidString: device),
             let translation = object(obj, "translation") as? NSObject,
             translation.responds(to: NSSelectorFromString("pid")),
             translation.responds(to: NSSelectorFromString("objectID")),
              let pid = translation.value(forKey: "pid") as? NSNumber,
              let oid = translation.value(forKey: "objectID") as? NSNumber,
              pid.int32Value > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout.size(ofValue: info))
        guard proc_pidinfo(pid.int32Value, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return "ax1:\(uuid.uuidString.lowercased()):\(pid.int32Value):\(info.pbi_start_tvsec)-\(info.pbi_start_tvusec):\(String(oid.uint64Value, radix: 16))"
    }

    /// Capability comes from the element, not its role or the wrapper's methods.
    static func adjustmentActions(_ obj: NSObject) -> [String] {
        let names = object(obj, "accessibilityActionNames") as? [String] ?? []
        return names.filter { $0 == "AXIncrement" || $0 == "AXDecrement" }
    }

    static func adjust(_ obj: NSObject, increment: Bool, deadline: Date = .distantFuture) -> Bool {
        let action = increment ? "AXIncrement" : "AXDecrement"
        guard adjustmentActions(obj).contains(action) else { return false }
        guard Date() < deadline else { return false }
        // AXP inherits NSAccessibilityElement's no-op BOOL methods, but
        // implements these void-returning translated actions itself.
        let selector = NSSelectorFromString(increment ? "performIncrementAction" : "performDecrementAction")
        if obj.responds(to: selector), let imp = obj.method(for: selector) {
            typealias Action = @convention(c) (AnyObject, Selector) -> Void
            unsafeBitCast(imp, to: Action.self)(obj, selector)
            return true // dispatched, NOT proof the app changed its value
        }
        return bool(obj, increment ? "accessibilityPerformIncrement" : "accessibilityPerformDecrement", default: false)
    }

    static func object(_ obj: NSObject, _ key: String) -> Any? {
        let selector = NSSelectorFromString(key)
        guard obj.responds(to: selector) else { return nil }
        return obj.perform(selector)?.takeUnretainedValue()
    }

    /// Non-empty string-valued property; returns `nil` for
    /// missing keys, non-string values, or empty strings.
    static func string(_ obj: NSObject, _ key: String) -> String? {
        guard let s = object(obj, key) as? String, !s.isEmpty else { return nil }
        return s
    }

    /// Like `string(_:_:)` but coerces `NSNumber` into its
    /// `stringValue`. Some accessibility-value properties return
    /// numbers (sliders, progress views, page pickers); we surface
    /// them as plain strings in the JSON so the column shape is
    /// stable.
    static func stringOrNumber(_ obj: NSObject, _ key: String) -> String? {
        let raw = object(obj, key)
        if let s = raw as? String { return s.isEmpty ? nil : s }
        if let n = raw as? NSNumber { return n.stringValue }
        return nil
    }

    /// Bool-valued property; returns `fallback` when the key is
    /// missing or holds a non-NSNumber value.
    static func bool(_ obj: NSObject, _ key: String, default fallback: Bool) -> Bool {
        let selector = NSSelectorFromString(key)
        guard obj.responds(to: selector), let imp = obj.method(for: selector) else { return fallback }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(imp, to: Getter.self)(obj, selector)
    }

    /// `accessibilityFrame` is a CGRect-returning Objective-C
    /// method, which can't ride through KVC's type-erased return —
    /// resolve via `class_getMethodImplementation` and a typed
    /// function-pointer cast. Returns `.zero` when the element
    /// doesn't respond to the selector.
    static func frame(of element: NSObject) -> CGRect {
        let sel = NSSelectorFromString("accessibilityFrame")
        guard element.responds(to: sel),
              let imp = class_getMethodImplementation(type(of: element), sel) else {
            return .zero
        }
        typealias Fn = @convention(c) (AnyObject, Selector) -> CGRect
        return unsafeBitCast(imp, to: Fn.self)(element, sel)
    }

    /// `accessibilityChildren` returns `[NSObject]` on real
    /// `AXPMacPlatformElement`s — we accept `nil`, an array of
    /// `NSObject` (the happy path), or anything else (treated as
    /// empty). Non-NSObject array entries are dropped silently.
    static func children(of element: NSObject) -> [NSObject] {
        guard let raw = object(element, "accessibilityChildren") else { return [] }
        if let arr = raw as? [NSObject] { return arr }
        return []
    }
}
