import AppKit
import VellforgeKit

/// A menu bar agent has no visible main menu, but key equivalents in its
/// windows still come from one. Without it ⌘V does nothing in a text field and
/// ⌘W doesn't close Settings.
@MainActor
enum MainMenu {

    static func install() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(ClosureMenuItem("About Vellforge") { AppActions.openSettings("about") })
        appMenu.addItem(.separator())
        appMenu.addItem(ClosureMenuItem("Settings…", key: ",") { AppActions.openSettings(nil) })
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Vellforge",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = window
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
