import AppKit
import VellforgeKit
import ApplicationServices
import CoreGraphics
import BarCore

/// Finds the menu bar items.
///
/// **The window list is useless for this.** `CGWindowListCopyWindowInfo` at the
/// status window level returns only ControlCenter's own items — the clock, the
/// battery, Wi-Fi. Third-party status items do not appear there at all: starting
/// an app that adds one changes nothing in the list. Verified by diffing the
/// list with and without a known status-item app running.
///
/// So the only route is ControlCenter's Accessibility tree, which exposes the
/// extras it draws, including third-party ones, with positions and often a name.
/// That makes Accessibility a **requirement** rather than a nicety.
@MainActor
enum MenuBarScanner {

    static func scan() -> [MenuBarItem] {
        guard AccessibilityPermission.isTrusted,
              let controlCenter = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.apple.controlcenter"
              })
        else { return [] }

        let app = AXUIElementCreateApplication(controlCenter.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)

        guard let extras = element(app, "AXExtrasMenuBar"),
              let children = value(extras, kAXChildrenAttribute as String) as? [AXUIElement]
        else { return [] }

        let items = children.enumerated().compactMap { index, child -> MenuBarItem? in
            guard let frame = frame(of: child) else { return nil }
            let name = [
                value(child, kAXTitleAttribute as String) as? String,
                value(child, kAXDescriptionAttribute as String) as? String,
                value(child, "AXIdentifier") as? String,
            ]
            .compactMap { $0 }
            .first { !$0.isEmpty }

            // No window ID is available here, so index by position — stable for
            // as long as the bar's arrangement is.
            return MenuBarItem(windowID: UInt32(index + 1), frame: frame, name: name)
        }
        return MenuBarLayout.plausible(items)
    }

    /// Whether the Accessibility route is actually working on this machine.
    /// Bar can list nothing without it, so it says so plainly rather
    /// than showing an empty list.
    static var canEnumerate: Bool {
        AccessibilityPermission.isTrusted && !scan().isEmpty
    }

    /// The strip of screen the items occupy, for a single capture.
    static func menuBarStrip(for items: [MenuBarItem]) -> CGRect? {
        guard !items.isEmpty else { return nil }
        return items.dropFirst().reduce(items[0].frame) { $0.union($1.frame) }
    }

    // MARK: AX plumbing

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success
        else { return nil }
        return result
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = value(element, attribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let posRaw = value(element, kAXPositionAttribute as String),
              CFGetTypeID(posRaw) == AXValueGetTypeID(),
              let sizeRaw = value(element, kAXSizeAttribute as String),
              CFGetTypeID(sizeRaw) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posRaw as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeRaw as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }
}
