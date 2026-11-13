import AppKit
import BarCore
import SwiftUI
import VellforgeKit

/// Hides menu bar clutter behind a divider you place with ⌘-drag.
/// Formerly Vellbar.
@MainActor
public final class BarAddOn: AddOn {

    public init() {}

    public let id = "bar"
    public let name = "Bar"
    public let tagline = "Hide menu bar clutter"
    public let summary = "Adds a divider and a chevron to the menu bar. Everything left of the "
        + "divider hides when you click the chevron. Hiding needs no permissions."
    public let symbolName = "menubar.rectangle"

    public let permissions = [
        PermissionUse(.accessibility, required: false,
                      reason: "Lists what's in your menu bar and clicks an item for you, even "
                            + "while it's hidden. macOS only shows other apps' menu bar items "
                            + "to apps you allow."),
        PermissionUse(.screenRecording, required: false,
                      reason: "Shows each item's real icon in the list. macOS offers no other way "
                            + "to read them, so Bar photographs one strip of the menu bar. It "
                            + "never records continuously, never saves an image and never sends one anywhere."),
    ]

    public let legacyApp: LegacyApp? = LegacyApp(
        name: "Vellbar",
        bundleID: "com.vellund.Vellbar",
        defaultsKeys: ["vellbar.sawSetup",
                       // Where the user ⌘-dragged the divider and chevron.
                       "NSStatusItem Preferred Position vellbar.toggle",
                       "NSStatusItem Preferred Position vellbar.separator"])

    private var separator: SeparatorController?
    private let icons = IconCapture()
    private var refreshTask: Task<Void, Never>?

    public var isRunning: Bool { separator != nil }

    public func start() {
        guard separator == nil else { return }
        Self.placeOnFirstRun()
        let controller = SeparatorController()
        controller.buildMenu = { [weak self] in self?.chevronMenu() ?? NSMenu() }
        controller.onCollapseChange = { [weak self] collapsed in self?.collapseChanged(collapsed) }
        separator = controller
        startCapturing()

        // Explain the drag once. Without it Bar looks broken on first run: it
        // adds two icons and appears to do nothing, because macOS put the
        // divider where it hides nothing.
        if !UserDefaults.standard.bool(forKey: "vellbar.sawSetup") {
            UserDefaults.standard.set(true, forKey: "vellbar.sawSetup")
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                Self.showHelp()
            }
        }
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        separator?.remove()
        separator = nil
    }

    /// Photograph the bar while it is expanded, so hidden items still have an
    /// icon to show. An item pushed off-screen cannot be captured, so the cache
    /// is the only way its icon survives collapsing.
    private func startCapturing() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.separator?.isCollapsed == false {
                    await self.icons.refresh(items: MenuBarScanner.scan())
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: Menus

    /// Bar's section of the main Vellforge menu.
    public func menuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = [toggleItem()]

        if separator?.wouldHideNothing == true {
            items.append(.readout("Nothing is set to hide yet"))
        }

        let list = NSMenuItem(title: "Menu Bar Items", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for item in listItems() { submenu.addItem(item) }
        list.submenu = submenu
        items.append(list)

        items.append(ClosureMenuItem("How to Choose What Hides…") { Self.showHelp() })
        return items
    }

    /// Right-click on the chevron: the list first, since that is why people
    /// right-click it.
    private func chevronMenu() -> NSMenu {
        let menu = NSMenu()
        for item in listItems() { menu.addItem(item) }
        menu.addItem(.separator())
        menu.addItem(toggleItem())
        menu.addItem(ClosureMenuItem("How to Choose What Hides…") { Self.showHelp() })
        menu.addItem(ClosureMenuItem("Vellforge Settings…") { AppActions.openSettings("bar") })
        return menu
    }

    private func toggleItem() -> NSMenuItem {
        let collapsed = separator?.isCollapsed == true
        return ClosureMenuItem(collapsed ? "Show Hidden Items" : "Hide Items") { [weak self] in
            self?.toggleCollapse()
        }
    }

    private func listItems() -> [NSMenuItem] {
        guard AccessibilityPermission.isTrusted else {
            // Not optional for the list: the window list does not expose
            // third-party status items at all, so Accessibility is the only way.
            return [.readout("Allow Accessibility to list items"),
                    ClosureMenuItem("Set Up…") { AppActions.openSettings("bar") }]
        }
        let items = MenuBarScanner.scan()
        guard !items.isEmpty else {
            return [.readout("Couldn't read the menu bar on this macOS")]
        }

        var rows: [NSMenuItem] = []
        if !ScreenRecordingPermission.isGranted {
            rows.append(.readout("Allow Screen Recording to see icons"))
        }
        for (index, item) in items.enumerated() {
            let point = item.clickPoint
            let row = ClosureMenuItem(Self.title(for: item, index: index)) { [weak self] in
                // The item may be pushed off-screen right now, so reveal,
                // click, restore.
                self?.separator?.revealing {
                    ItemActivator.click(at: CGPoint(x: point.x, y: point.y))
                }
            }
            if let icon = icons.image(for: item.windowID) {
                icon.size = NSSize(width: 18, height: 18)
                row.image = icon
            }
            rows.append(row)
        }
        return rows
    }

    /// The icon carries the identity, so the label only has to disambiguate.
    private static func title(for item: MenuBarItem, index: Int) -> String {
        if let name = item.name, !name.isEmpty { return name }
        return item.looksLikeText ? "Text item \(index + 1)" : "Item \(index + 1)"
    }

    private func toggleCollapse() {
        guard let separator else { return }
        separator.setCollapsed(!separator.isCollapsed)
    }

    private func collapseChanged(_ collapsed: Bool) {
        if collapsed {
            // Collapsing with nothing left of the divider looks exactly like a
            // broken app: the chevron flips and nothing happens. Say why.
            if separator?.wouldHideNothing == true, AccessibilityPermission.isTrusted {
                Feedback.show("Nothing is left of Bar's ☰ divider, so there's nothing to hide. "
                              + "Hold ⌘ and drag icons to the left of it.", duration: 5)
            }
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                await icons.refresh(items: MenuBarScanner.scan(), force: true)
            }
        }
    }

    /// Where macOS remembers a menu bar item's place, by the item's autosave
    /// name. Lower numbers sit further right, next to Control Center.
    static func positionKey(_ autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }

    /// macOS puts a new menu bar item at the far left. On a full menu bar
    /// that is behind the camera notch, out of sight, and with the divider
    /// at the far left collapsing hides nothing at all. So the first time,
    /// put the chevron and divider at the right end, just left of the
    /// Vellforge icon: collapsing then hides everything else, and the user
    /// ⌘-drags back out whatever should stay. Never touches a position the
    /// user (or the import from Vellbar) has already set.
    static func placeOnFirstRun() {
        let defaults = UserDefaults.standard
        let toggle = positionKey("vellbar.toggle"), divider = positionKey("vellbar.separator")
        guard defaults.object(forKey: toggle) == nil, defaults.object(forKey: divider) == nil
        else { return }
        defaults.set(1.0, forKey: toggle)
        defaults.set(2.0, forKey: divider)
    }

    static func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Click the chevron to hide icons"
        alert.informativeText = """
            Bar starts with its chevron and ☰ divider at the right end of the \
            menu bar, so clicking the chevron hides every icon to the left of ☰.

            To keep an icon on show, hold ⌘ and drag it to the right of ☰. \
            To hide less, ⌘-drag ☰ itself further left.

            Right-click the chevron any time for the full list; you can open \
            any item from there, even while it's hidden.
            """
        alert.addButton(withTitle: "Got it")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: Settings and diagnostics

    public func makeSettingsView() -> AnyView {
        AnyView(BarSettingsView())
    }

    public func diagnostics() -> String {
        var lines = BarDiagnostics.report()
        lines += "\n  divider collapsed: \(separator?.isCollapsed.description ?? "not running")"
        lines += "\n  would hide nothing: \(separator?.wouldHideNothing.description ?? "-")"
        lines += "\n  divider at x:       \(separator?.separatorX.map { String(Int($0)) } ?? "-")"
        return lines
    }
}

struct BarSettingsView: View {
    var body: some View {
        Section {
            HStack {
                Text("Click the chevron to hide every icon left of Bar's ☰ divider. Hold ⌘ and drag an icon to the right of ☰ to keep it on show. Right-click the chevron for the list.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show Me How") { BarAddOn.showHelp() }
            }
        } header: {
            Text("Choosing what hides")
        }
    }
}
