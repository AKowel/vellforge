import AppKit
import SnapCore
import VellforgeKit

/// Snap's section of the menu: the grid picker, every command with its
/// shortcut, and saved layouts.
@MainActor
enum SnapMenu {

    static func items() -> [NSMenuItem] {
        [gridItem(), commandsItem(), layoutsItem()]
    }

    // MARK: Grid picker

    private static func gridItem() -> NSMenuItem {
        let item = NSMenuItem()
        let picker = GridPickerView()
        picker.frame = NSRect(origin: .zero, size: picker.intrinsicContentSize)
        picker.onSelect = { zone in
            if case .failure(let error) = SnapEngine.perform(zone) {
                Feedback.show(error.localizedDescription)
            }
        }
        item.view = picker
        return item
    }

    // MARK: Commands

    /// Seventeen commands would swamp a menu shared with other add-ons, so they
    /// live one level down. The shortcut beside each row is still the cheapest
    /// way for people to learn them.
    private static func commandsItem() -> NSMenuItem {
        let root = NSMenuItem(title: "Move Window", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        var lastGroup: String?
        for command in Command.allCases {
            if let lastGroup, lastGroup != command.group {
                submenu.addItem(.separator())
            }
            lastGroup = command.group
            submenu.addItem(item(for: command))
        }
        root.submenu = submenu
        return root
    }

    private static func item(for command: Command) -> NSMenuItem {
        let item = ClosureMenuItem(command.title) { CommandRunner.run(command) }

        // A shortcut the system refused to register is worse than none, because
        // the menu would advertise a key combination that does nothing.
        if !BindingStore.shared.conflicted.contains(command),
           let binding = BindingStore.shared.bindings[command],
           let equivalent = binding.menuKeyEquivalent {
            item.keyEquivalent = equivalent
            item.keyEquivalentModifierMask = binding.appKitModifiers
        }
        return item
    }

    // MARK: Saved layouts

    private static func layoutsItem() -> NSMenuItem {
        let root = NSMenuItem(title: "Layouts", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let saved = LayoutStore.shared.layouts
        if saved.isEmpty {
            submenu.addItem(.readout("No saved layouts"))
        } else {
            for layout in saved {
                let item = NSMenuItem(title: layout.name, action: nil, keyEquivalent: "")
                item.submenu = layoutSubmenu(for: layout)
                submenu.addItem(item)
            }
        }

        submenu.addItem(.separator())
        submenu.addItem(ClosureMenuItem("Save Current Layout…") { saveLayout() })

        root.submenu = submenu
        return root
    }

    private static func layoutSubmenu(for layout: SavedLayout) -> NSMenu {
        let menu = NSMenu()
        let count = layout.windows.count
        menu.addItem(.readout("\(count) window\(count == 1 ? "" : "s")"))
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem("Restore") {
            Feedback.show(LayoutStore.shared.restore(layout).message)
        })
        menu.addItem(ClosureMenuItem("Restore and Open Missing Apps") {
            Feedback.show(LayoutStore.shared.restore(layout, relaunchMissing: true).message)
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Update to Current Arrangement") {
            LayoutStore.shared.update(id: layout.id)
            Feedback.show("Layout updated.")
        })
        menu.addItem(ClosureMenuItem("Rename…") {
            guard let name = prompt(title: "Rename Layout", message: "",
                                    placeholder: layout.name) else { return }
            LayoutStore.shared.rename(id: layout.id, to: name)
        })
        menu.addItem(ClosureMenuItem("Delete") { delete(layout) })
        return menu
    }

    private static func saveLayout() {
        guard let name = prompt(title: "Save Layout",
                                message: "Capture the position of every open window.",
                                placeholder: "Coding") else { return }
        if let layout = LayoutStore.shared.capture(named: name) {
            Feedback.show("Saved “\(layout.name)”: \(layout.windows.count) windows.")
        } else {
            Feedback.show("Couldn't find any windows to save.")
        }
    }

    private static func delete(_ layout: SavedLayout) {
        let alert = NSAlert()
        alert.messageText = "Delete “\(layout.name)”?"
        alert.informativeText = "This can't be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        LayoutStore.shared.delete(id: layout.id)
    }

    private static func prompt(title: String, message: String, placeholder: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = placeholder
        field.stringValue = placeholder
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
