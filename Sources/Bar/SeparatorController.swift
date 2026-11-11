import AppKit

/// Hides menu bar clutter using the one mechanism macOS actually allows.
///
/// There is no API to hide another app's status item. What you *can* do is make
/// your own item enormously wide: items are laid out right to left, so a very
/// wide one shoves everything to its left past the edge of the screen. Drag the
/// separator to wherever hiding should begin — everything left of it disappears
/// when collapsed.
///
/// Crude, but it is what Hidden Bar and Dozer do, it needs no permissions at
/// all, and unlike pixel-capture approaches it cannot break on a macOS update.
@MainActor
final class SeparatorController {

    private let toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let separator = NSStatusBar.system.statusItem(withLength: expandedLength)

    private static let expandedLength: CGFloat = 14
    /// Wide enough to push everything off any display anyone owns.
    private static let collapsedLength: CGFloat = 10_000

    /// What to show when the user asks what is hidden.
    var buildMenu: (() -> NSMenu)?

    private(set) var isCollapsed: Bool {
        didSet {
            UserDefaults.standard.set(isCollapsed, forKey: "vellbar.collapsed")
            apply()
        }
    }

    init() {
        isCollapsed = UserDefaults.standard.bool(forKey: "vellbar.collapsed")

        // Autosave names let the user ⌘-drag both items and have the positions
        // stick — which is the whole configuration interface.
        toggle.autosaveName = "vellbar.toggle"
        separator.autosaveName = "vellbar.separator"

        if let button = toggle.button {
            button.target = self
            button.action = #selector(toggleClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        if let button = separator.button {
            button.image = NSImage(systemSymbolName: "line.3.horizontal.decrease",
                                   accessibilityDescription: "Vellforge Bar divider")
            button.image?.isTemplate = true
            button.appearsDisabled = true
        }
        apply()
    }

    @objc private func toggleClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            isCollapsed.toggle()
        }
    }

    private func showMenu() {
        guard let menu = buildMenu?() else { return }
        toggle.menu = menu
        toggle.button?.performClick(nil)
        // Detach again so the next left click toggles instead of reopening.
        toggle.menu = nil
    }

    private func apply() {
        separator.length = isCollapsed ? Self.collapsedLength : Self.expandedLength
        toggle.button?.image = NSImage(
            systemSymbolName: isCollapsed ? "chevron.left" : "chevron.right",
            accessibilityDescription: isCollapsed ? "Show hidden items" : "Hide items")
        toggle.button?.image?.isTemplate = true
    }

    func setCollapsed(_ collapsed: Bool) { isCollapsed = collapsed }

    /// Take both icons out of the menu bar, for when Bar is switched off.
    /// Expand first, so nothing stays pushed off-screen.
    func remove() {
        separator.length = Self.expandedLength
        NSStatusBar.system.removeStatusItem(separator)
        NSStatusBar.system.removeStatusItem(toggle)
    }

    /// Where the divider currently sits, in screen coordinates.
    ///
    /// Needed because an app cannot position its own status item — macOS drops
    /// new ones at the left end and only a ⌘-drag moves them. Knowing where the
    /// divider ended up is the only way to tell the user whether collapsing
    /// would actually hide anything.
    var separatorX: CGFloat? {
        guard let window = separator.button?.window else { return nil }
        return window.frame.minX
    }

    /// True when the divider is so far left that collapsing achieves nothing —
    /// which is exactly where macOS puts it on first launch.
    var wouldHideNothing: Bool {
        guard let x = separatorX else { return true }
        return !MenuBarScanner.scan().contains { $0.frame.maxX <= x }
    }

    /// Reveal briefly, run something, then restore — used when activating an
    /// item that is currently pushed off-screen.
    func revealing(_ work: @escaping @MainActor () -> Void) {
        let wasCollapsed = isCollapsed
        if wasCollapsed { isCollapsed = false }
        Task { @MainActor in
            // Give the menu bar a moment to lay out before clicking into it.
            try? await Task.sleep(for: .milliseconds(180))
            work()
            if wasCollapsed {
                try? await Task.sleep(for: .milliseconds(400))
                isCollapsed = true
            }
        }
    }
}
