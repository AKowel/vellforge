import AppKit
import Bar
import Buttons
import Scroll
import Snap
import VellforgeKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Every add-on Vellforge ships. A new one is one more entry here.
    let registry = AddOnRegistry(addOns: [SnapAddOn(), ScrollAddOn(), BarAddOn(), ButtonsAddOn()])
    let updater = Updater()

    private var statusMenu: StatusMenuController?
    private var settings: SettingsWindowController?
    private var welcome: WelcomeWindowController?

    static let welcomeDoneKey = "vellforge.welcomeDone"

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()

        // The main icon first. Status items are laid out right to left in the
        // order they are created, so this one sits to the right of Bar's
        // divider and can never be hidden by it.
        statusMenu = StatusMenuController(app: self)
        AppActions.openSettings = { [weak self] pane in self?.showSettings(pane: pane) }

        PermissionMonitor.shared.onChange = { [weak self] in self?.registry.refresh() }
        PermissionMonitor.shared.start()
        watchLegacyApps()

        if UserDefaults.standard.bool(forKey: Self.welcomeDoneKey) {
            registry.refresh()
        } else {
            showWelcome()
        }

        // `open Vellforge.app --args -vellforge.open snap` opens a window at
        // launch ("welcome", "general", "about", or an add-on id). Handy for
        // screenshots and for testing a pane. Arguments are never stored.
        if let pane = UserDefaults.standard.string(forKey: "vellforge.open") {
            pane == "welcome" ? showWelcome() : showSettings(pane: pane)
        }

        // `Vellforge -vellforge.dumpMenu YES` (the binary, from a terminal)
        // prints the menu and the diagnostics report, then quits.
        if UserDefaults.standard.bool(forKey: "vellforge.dumpMenu") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                print(self.statusMenu?.dumpedMenu() ?? "")
                print("\n" + self.diagnosticsReport())
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        registry.stopAll()
    }

    /// Opening Vellforge again from Finder or Spotlight while it is already
    /// running opens Settings, so it never seems to do nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(pane: nil)
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Windows

    func showSettings(pane: String?) {
        if settings == nil { settings = SettingsWindowController(app: self) }
        settings?.show(pane: pane)
    }

    func showWelcome() {
        if welcome == nil {
            welcome = WelcomeWindowController(app: self) { [weak self] in
                self?.welcome = nil
            }
        }
        welcome?.show()
    }

    /// Switch an add-on on and, if it needs a permission it doesn't have yet,
    /// ask for it straight away rather than leaving it silently waiting.
    func enable(_ addOn: any AddOn, _ on: Bool) {
        registry.setEnabled(on, for: addOn)
        if on, let missing = registry.missingPermissions(for: addOn).first {
            missing.request()
        }
    }

    func showDiagnostics() {
        DiagnosticsWindow.show(title: "Vellforge diagnostics", report: diagnosticsReport())
    }

    private func diagnosticsReport() -> String {
        var lines = [
            "Vellforge \(AppInfo.version) (\(AppInfo.build))",
            "bundle: \(Bundle.main.bundleIdentifier ?? "?")",
            "path:   \(Bundle.main.bundlePath)",
            "macOS:  \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "updates: \(updater.isAvailable ? "on" : "off in this build")",
            "menu bar icon: \(statusMenu?.iconPlacement ?? "-")",
            "",
            "PERMISSIONS",
        ]
        for permission in Permission.allCases {
            lines.append("  \(permission.title): \(permission.isGranted ? "granted" : "not granted")")
        }
        lines.append("")
        lines.append("ADD-ONS")
        for addOn in registry.addOns {
            let state = !registry.isEnabled(addOn) ? "off"
                : addOn.isRunning ? "running"
                : "waiting for " + registry.missingPermissions(for: addOn).map(\.title).joined(separator: ", ")
            var line = "  \(addOn.name): \(state)"
            if let legacy = addOn.legacyApp, LegacyApps.isRunning(legacy) {
                line += "  (\(legacy.name) is also running)"
            }
            lines.append(line)
        }
        for addOn in registry.enabledAddOns {
            let report = addOn.diagnostics()
            if !report.isEmpty { lines += ["", report] }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Old standalone apps

    /// When an old app quits, the add-on that replaces it may need to start
    /// over: Vellsnap held the shortcuts Snap wants.
    private func watchLegacyApps() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, let bundleID else { return }
                for addOn in self.registry.addOns where addOn.legacyApp?.bundleID == bundleID {
                    self.registry.restart(addOn)
                }
            }
        }
    }
}
