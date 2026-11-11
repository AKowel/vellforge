import AppKit
import SwiftUI
import VellforgeKit

/// Window snapping, keyboard layouts and saved arrangements. Formerly Vellsnap.
@MainActor
public final class SnapAddOn: AddOn {

    public init() {}

    public let id = "snap"
    public let name = "Snap"
    public let tagline = "Window snapping and layouts"
    public let summary = "Drag a window to a screen edge to snap it, use keyboard shortcuts, "
        + "or save every window's position and restore it later."
    public let symbolName = "rectangle.split.2x1"

    public let permissions = [
        PermissionUse(.accessibility, required: true,
                      reason: "macOS only lets an app move another app's windows if you allow it. "
                            + "Snap uses it for exactly that and nothing else."),
    ]

    public let legacyApp: LegacyApp? = LegacyApp(
        name: "Vellsnap",
        bundleID: "com.vellund.Vellsnap",
        defaultsKeys: ["vellsnap.dragSnap", "vellsnap.layoutBar",
                       "vellsnap.gap", "vellsnap.bindings"],
        supportFiles: ["layouts.json"])

    public private(set) var isRunning = false

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        BindingStore.shared.isActive = true
        BindingStore.shared.reregister()
        DragSnapController.shared.isActive = true
        DragSnapController.shared.start()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        BindingStore.shared.isActive = false
        HotKeyManager.shared.unregisterAll()
        DragSnapController.shared.isActive = false
        DragSnapController.shared.stop()
    }

    public func menuItems() -> [NSMenuItem] {
        SnapMenu.items()
    }

    public func makeSettingsView() -> AnyView {
        AnyView(SnapSettingsView())
    }

    public func reloadAfterImport() {
        BindingStore.shared.reload()
        LayoutStore.shared.reload()
    }

    public func diagnostics() -> String {
        let conflicted = BindingStore.shared.conflicted.map(\.title).sorted()
        return """
            SNAP
              running:              \(isRunning)
              drag to snap:         \(DragSnapController.isEnabled)
              layout chooser:       \(DragSnapController.layoutBarEnabled)
              gap:                  \(Int(SnapEngine.gap)) pt
              shortcuts registered: \(isRunning ? BindingStore.shared.bindings.count - conflicted.count : 0)
              shortcuts taken by another app: \(conflicted.isEmpty ? "none" : conflicted.joined(separator: ", "))
              saved layouts:        \(LayoutStore.shared.layouts.count)
              displays:             \(ScreenBridge.displays().count)
            """
    }
}
