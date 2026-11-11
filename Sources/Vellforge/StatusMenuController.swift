import AppKit
import VellforgeKit

/// The one Vellforge icon in the menu bar, and its menu: a section for each
/// add-on that is switched on, then the app's own items.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private unowned let app: AppDelegate

    init(app: AppDelegate) {
        self.app = app
        super.init()

        statusItem.autosaveName = "vellforge.main"
        statusItem.button?.image = Self.mark()
        statusItem.button?.setAccessibilityLabel("Vellforge")
        Feedback.anchor = statusItem.button

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    /// The Vellforge mark from the website (an outline, one solid pane and two
    /// fainter ones), as a template so it follows the menu bar's colour.
    private static func mark() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            let outline = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 15, height: 15),
                                       xRadius: 4, yRadius: 4)
            outline.lineWidth = 1.3
            outline.stroke()

            func pane(_ rect: NSRect, _ alpha: CGFloat) {
                NSColor.black.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            }
            pane(NSRect(x: 4.5, y: 4.5, width: 4, height: 9), 1)
            pane(NSRect(x: 9.5, y: 4.5, width: 4, height: 4), 0.6)
            pane(NSRect(x: 9.5, y: 9.5, width: 4, height: 4), 0.4)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The menu as indented text, for `-vellforge.dumpMenu YES`: lets a test
    /// see what each add-on contributes without anyone clicking the icon.
    func dumpedMenu() -> String {
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        func lines(_ menu: NSMenu, depth: Int) -> [String] {
            menu.items.flatMap { item -> [String] in
                let pad = String(repeating: "  ", count: depth)
                var title = item.isSeparatorItem ? "----" : item.title
                if item.view != nil { title = "[custom view]" }
                if item.isSectionHeader { title = "## " + title }
                if item.state == .on { title = "✓ " + title }
                if !item.isEnabled && !item.isSeparatorItem && !item.isSectionHeader { title += "  (readout)" }
                if !item.keyEquivalent.isEmpty { title += "  [\(item.keyEquivalentModifierMask.rawValue >> 16):\(item.keyEquivalent.unicodeScalars.map { String($0.value, radix: 16) }.joined())]" }
                return [pad + title] + (item.submenu.map { lines($0, depth: depth + 1) } ?? [])
            }
        }
        return lines(menu, depth: 0).joined(separator: "\n")
    }

    /// Rebuilt every time it opens, so permission state, shortcuts and add-on
    /// readouts are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let registry = app.registry
        let enabled = registry.enabledAddOns

        if enabled.isEmpty {
            menu.addItem(.readout("No add-ons are switched on"))
            menu.addItem(ClosureMenuItem("Choose Add-ons…") { [weak app] in
                app?.showSettings(pane: nil)
            })
        }

        for (index, addOn) in enabled.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            menu.addItem(.sectionHeader(title: addOn.name))

            // An old copy still running fights the add-on: Vellscroll plus
            // Scroll flips scrolling twice, which cancels out.
            if let legacy = addOn.legacyApp, LegacyApps.isRunning(legacy) {
                menu.addItem(.readout("\(legacy.name) is still running"))
                menu.addItem(ClosureMenuItem("Quit \(legacy.name)") {
                    Task { await LegacyApps.quit(legacy) }
                })
            }

            let missing = registry.missingPermissions(for: addOn)
            if missing.isEmpty {
                for item in addOn.menuItems() { menu.addItem(item) }
            } else {
                let names = missing.map(\.title).joined(separator: " and ")
                menu.addItem(.readout("Needs \(names) access"))
                menu.addItem(ClosureMenuItem("Grant Access…") { [weak app] in
                    missing.first?.requestAndOpenSettings()
                    app?.showSettings(pane: addOn.id)
                })
            }
        }

        menu.addItem(.separator())

        let updater = app.updater
        if updater.updateIsWaiting {
            menu.addItem(ClosureMenuItem("Update Available…") { updater.checkForUpdates() })
        }
        menu.addItem(ClosureMenuItem("Settings…", key: ",") { [weak app] in
            app?.showSettings(pane: nil)
        })
        let check = ClosureMenuItem("Check for Updates…") { updater.checkForUpdates() }
        check.isEnabled = updater.isAvailable
        menu.addItem(check)
        menu.addItem(ClosureMenuItem("Vellforge is free — support it") {
            NSWorkspace.shared.open(Links.donate)
        })

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Vellforge",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }
}
