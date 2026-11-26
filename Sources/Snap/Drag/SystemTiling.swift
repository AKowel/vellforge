import AppKit
import VellforgeKit

/// macOS 15 and later tile a window you drag to a screen edge on their own.
/// That listens for exactly the gesture drag-to-snap does, so with both on,
/// every edge drop is handled twice: macOS animates the window into its tile
/// while Snap writes its own frame, and what you get depends on which lands
/// last.
///
/// The settings live in WindowManager's defaults, under the keys System
/// Settings › Desktop & Dock › Windows writes. Unset means on, which is how
/// macOS ships.
@MainActor
enum SystemTiling {

    private static let domain = "com.apple.WindowManager" as CFString

    /// "Drag windows to screen edges to tile" and "Drag windows to menu bar to
    /// fill screen". The ⌥-drag accelerator is left alone: it only acts while
    /// ⌥ is held, which Snap never asks for.
    private static let keys = ["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag"]

    private static let promptedKey = "vellsnap.askedAboutSystemTiling"

    static var exists: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0))
    }

    static var isOn: Bool {
        guard exists else { return false }
        CFPreferencesAppSynchronize(domain)
        return keys.contains { key in
            (CFPreferencesCopyAppValue(key as CFString, domain) as? Bool) ?? true
        }
    }

    /// Returns whether macOS now reads the settings as off.
    @discardableResult
    static func turnOff() -> Bool {
        for key in keys {
            CFPreferencesSetAppValue(key as CFString, kCFBooleanFalse, domain)
        }
        CFPreferencesAppSynchronize(domain)
        return !isOn
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Ask once, the first time Snap runs with both on. After that the choice
    /// stays in Snap's settings, where the conflict is shown until it is gone.
    static func askOnceIfConflicting() {
        guard DragSnapController.isEnabled, isOn,
              !UserDefaults.standard.bool(forKey: promptedKey) else { return }
        UserDefaults.standard.set(true, forKey: promptedKey)

        let alert = NSAlert()
        alert.messageText = "macOS is snapping windows too"
        alert.informativeText = """
            macOS's own tiling reacts to the same drag to a screen edge as Snap, \
            so both try to move the window when you let go, and the result is \
            unpredictable.

            Turn off macOS's edge tiling to let Snap handle drags. You can turn \
            it back on in System Settings › Desktop & Dock.
            """
        alert.addButton(withTitle: "Turn Off macOS Tiling")
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Use macOS's Instead")
        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if !turnOff() {
                Feedback.show("macOS didn't take the change. Turn tiling off in Desktop & Dock.",
                              duration: 5)
                openSystemSettings()
            }
        case .alertThirdButtonReturn:
            DragSnapController.isEnabled = false
        default:
            break
        }
    }
}
