import AppKit
import SwiftUI

/// One tool inside Vellforge: Snap, Scroll, Bar, and whatever comes next.
///
/// The app knows nothing about what an add-on does. It switches each one on or
/// off, makes sure the permissions it needs are granted before starting it,
/// gives it a section of the menu and a pane in Settings, and that is all.
/// Adding a tool means writing one type that conforms to this, and adding it
/// to the list in the app.
@MainActor
public protocol AddOn: AnyObject {
    /// Stable identifier, used in stored settings. Never change it.
    var id: String { get }
    /// Short name shown everywhere: "Snap".
    var name: String { get }
    /// What it does, in a few words.
    var tagline: String { get }
    /// One or two sentences for the welcome window and Settings.
    var summary: String { get }
    /// SF Symbol for Settings and the welcome window.
    var symbolName: String { get }

    /// Every permission it touches, required or optional, with the reason.
    var permissions: [PermissionUse] { get }

    /// The standalone app this add-on replaces, if any, so its settings can be
    /// brought over and a copy still running can be spotted.
    var legacyApp: LegacyApp? { get }

    /// True between `start()` and `stop()`.
    var isRunning: Bool { get }

    /// Called only once every required permission is granted.
    func start()
    func stop()

    /// This add-on's section of the menu bar menu. Rebuilt every time the menu
    /// opens, so it can show live state.
    func menuItems() -> [NSMenuItem]

    /// The add-on's own pane in Settings, below the on/off switch and the
    /// permission rows the app draws itself.
    func makeSettingsView() -> AnyView

    /// A plain-text report for the diagnostics window.
    func diagnostics() -> String

    /// Settings were just copied in from the old standalone app: re-read them.
    func reloadAfterImport()
}

extension AddOn {
    public var requiredPermissions: [Permission] {
        permissions.filter(\.isRequired).map(\.permission)
    }

    public var legacyApp: LegacyApp? { nil }
    public func diagnostics() -> String { "" }
    public func reloadAfterImport() {}
}
