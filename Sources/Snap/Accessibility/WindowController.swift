import AppKit
import ApplicationServices

/// Thin wrapper over the Accessibility API for reading and writing window
/// frames. All coordinates here are **Accessibility coordinates** (top-left
/// origin) — conversion happens in `SnapEngine`.
@MainActor
enum WindowController {

    /// Accessibility calls are synchronous IPC into the target process. Without
    /// a timeout, a beachballed app blocks us for the system default and takes
    /// the menu bar down with it. This one line is the difference between a
    /// utility that feels instant and one that periodically freezes.
    private static let messagingTimeout: Float = 0.25

    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)

        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard result == .success, let windowRef else { return nil }
        guard CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }

        let window = windowRef as! AXUIElement
        AXUIElementSetMessagingTimeout(window, messagingTimeout)
        return window
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = point(window, kAXPositionAttribute),
              let size = size(window, kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Native full-screen windows cannot be moved at all. Detect and skip them
    /// rather than failing silently.
    static func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            window, "AXFullScreen" as CFString, &value)
        guard result == .success, let value else { return false }
        return (value as? Bool) ?? false
    }

    static func isResizable(_ window: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(
            window, kAXSizeAttribute as CFString, &settable)
        return result == .success && settable.boolValue
    }

    /// Write a frame, then verify it took.
    ///
    /// Order matters: a window pinned against a screen edge may refuse to grow
    /// until it has been moved, silently clamping the first size write. Setting
    /// position, then size, then position again handles both orderings.
    @discardableResult
    static func setFrame(_ rect: CGRect, of window: AXUIElement) -> Bool {
        apply(rect, to: window)

        // Some apps (Electron, JetBrains, anything AWT-backed) apply the change
        // late or partially. One retry catches most of them; beyond that the
        // window genuinely will not move and we leave it alone.
        if let actual = frame(of: window), !actual.approximatelyEquals(rect) {
            apply(rect, to: window)
        }

        guard let actual = frame(of: window) else { return false }
        return actual.approximatelyEquals(rect)
    }

    private static func apply(_ rect: CGRect, to window: AXUIElement) {
        setPoint(window, kAXPositionAttribute, rect.origin)
        setSize(window, kAXSizeAttribute, rect.size)
        setPoint(window, kAXPositionAttribute, rect.origin)
    }

    // MARK: - AXValue plumbing

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private static func setPoint(_ element: AXUIElement, _ attribute: String, _ point: CGPoint) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }

    private static func setSize(_ element: AXUIElement, _ attribute: String, _ size: CGSize) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }
}

extension CGRect {
    /// Windows land a point or two off constantly — apps round, snap to their
    /// own increments, or enforce minimum sizes. Exact equality is the wrong
    /// test for "did this work".
    func approximatelyEquals(_ other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

// MARK: - Enumerating every window on screen
//
// Needed by saved layouts, which operate on the whole desktop rather than the
// focused window.

extension WindowController {

    struct LiveWindow {
        let element: AXUIElement
        let bundleID: String
        let title: String
        let axIndex: Int
    }

    /// Every ordinary window of every ordinary app.
    ///
    /// Agents and accessory apps are skipped (Vellforge itself included), as are
    /// minimised windows, which cannot be positioned meaningfully.
    static func allWindows() -> [LiveWindow] {
        var result: [LiveWindow] = []

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier
            else { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.25)

            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                    appElement, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement]
            else { continue }

            for (index, window) in windows.enumerated() {
                AXUIElementSetMessagingTimeout(window, 0.25)
                guard !isMinimized(window) else { continue }
                result.append(LiveWindow(element: window,
                                         bundleID: bundleID,
                                         title: string(window, kAXTitleAttribute) ?? "",
                                         axIndex: index))
            }
        }
        return result
    }

    static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                window, kAXMinimizedAttribute as CFString, &value) == .success,
              let value else { return false }
        return (value as? Bool) ?? false
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        return value as? String
    }
}
