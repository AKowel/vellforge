import AppKit
import ServiceManagement

/// Outward links, all routed through vellforge.com so destinations can change
/// without shipping a new build.
public enum Links {
    public static let site   = URL(string: "https://vellforge.com")!
    public static let donate = URL(string: "https://vellforge.com/donate")!
    public static let docs   = URL(string: "https://vellforge.com/docs")!
    public static let source = URL(string: "https://github.com/AKowel/vellforge")!

    /// The docs section for one add-on.
    public static func docs(for addOnID: String) -> URL {
        URL(string: "https://vellforge.com/docs#\(addOnID)")!
    }
}

/// Transient messages, anchored to the menu bar icon.
///
/// Failures here are routine (plenty of windows refuse to be resized), so they
/// get a popover that fades on its own, never a modal that demands
/// acknowledgement for something the user cannot fix.
@MainActor
public enum Feedback {

    public static weak var anchor: NSStatusBarButton?
    private static var current: NSPopover?

    public static func show(_ message: String, duration: TimeInterval = 2.5) {
        guard let anchor else { return }

        current?.performClose(nil)

        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 12)
        label.frame = NSRect(x: 14, y: 10, width: 260, height: 36)
        label.alignment = .center

        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 288, height: 56))
        controller.view.addSubview(label)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        current = popover

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            if current === popover {
                popover.performClose(nil)
                current = nil
            }
        }
    }
}

@MainActor
public enum LaunchAtLogin {

    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns whether the change took. Fails while running from a build
    /// folder, which is the normal development case, so it says so.
    @discardableResult
    public static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change launch at login"
            alert.informativeText = error.localizedDescription
                + "\n\nMove Vellforge to your Applications folder and try again."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return false
        }
    }
}

@MainActor
public enum AppInfo {
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
    public static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// Start a fresh copy and quit this one. Needed after a Screen Recording
    /// grant, which macOS only honours from the next launch.
    public static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    /// Where Vellforge keeps its own files.
    public static var supportDirectory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let dir = base.appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// A menu item that runs a closure, so add-ons don't need a target object and
/// a selector for every row.
@MainActor
public final class ClosureMenuItem: NSMenuItem {

    private let handler: @MainActor () -> Void

    public init(_ title: String,
                key: String = "",
                checked: Bool? = nil,
                handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        if let checked { state = checked ? .on : .off }
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}

extension NSMenuItem {
    /// A non-clickable informational row.
    @MainActor
    public static func readout(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

/// Shows a plain-text report with a Copy button, and keeps a copy on disk so a
/// user can attach it to an issue.
@MainActor
public enum DiagnosticsWindow {

    public static func show(title: String, report: String) {
        if let dir = AppInfo.supportDirectory {
            try? report.write(to: dir.appendingPathComponent("diagnostics.txt"),
                              atomically: true, encoding: .utf8)
        }

        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 360))
        text.string = report
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let scroll = NSScrollView(frame: text.frame)
        scroll.documentView = text
        scroll.hasVerticalScroller = true

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "A copy is saved in ~/Library/Application Support/"
            + (Bundle.main.bundleIdentifier ?? "") + "/diagnostics.txt"
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "Close")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
        }
    }
}

/// Things an add-on can ask the app to do. The app fills these in at launch;
/// add-ons never need to know about the app's own types.
@MainActor
public enum AppActions {
    /// Open Settings, at an add-on's pane when given its id.
    public static var openSettings: (_ addOnID: String?) -> Void = { _ in }
}

/// Puts Vellforge's windows where the user is looking.
///
/// `NSWindow.center()` uses the "main" screen, which for a menu bar app with
/// no window of its own can be any display, so on a multi-monitor setup the
/// welcome window opened on a screen nobody was looking at. The pointer is a
/// far better guess. And macOS 14 may refuse to activate an app the user
/// didn't just click, so the window is ordered front regardless.
@MainActor
public enum WindowPlacement {

    public static var activeScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Centre on the pointer's display, a little above the middle like
    /// `center()` does.
    public static func centerOnActiveScreen(_ window: NSWindow) {
        guard let visible = activeScreen?.visibleFrame else { window.center(); return }
        let size = window.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: min(visible.maxY - size.height,
                                    visible.midY - size.height / 2 + visible.height / 10))
        window.setFrameOrigin(NSPoint(x: origin.x, y: max(visible.minY, origin.y)))
    }

    /// Show it on the current Space, including over a full-screen app.
    public static func bringToFront(_ window: NSWindow) {
        window.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
