import AppKit
import SnapCore

/// Translates `NSScreen` into the AppKit-free `Display` the geometry core uses.
@MainActor
enum ScreenBridge {

    /// The reference point for every AppKit ↔ Accessibility conversion. Always
    /// the *primary* screen, never the screen a window happens to be on.
    static var primaryMaxY: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    static func displays() -> [Display] {
        NSScreen.screens.enumerated().map { index, screen in
            Display(id: stableID(for: screen) ?? "index-\(index)",
                    frame: screen.frame,
                    visibleFrame: screen.visibleFrame)
        }
    }

    /// A UUID that survives unplugging and replugging a monitor. Screen indices
    /// do not — they shuffle on reconnect, which is why saved layouts key off
    /// this instead.
    static func stableID(for screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
