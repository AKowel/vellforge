import AppKit
import ScrollCore
import SwiftUI
import VellforgeKit

/// Scroll direction per device, so trackpad and mouse can go opposite ways.
/// Formerly Vellscroll.
@MainActor
public final class ScrollAddOn: AddOn {

    public init() {}

    public let id = "scroll"
    public let name = "Scroll"
    public let tagline = "Scroll direction per device"
    public let summary = "macOS has one natural scrolling switch for every device. Scroll lets "
        + "the trackpad and the mouse wheel go opposite ways."
    public let symbolName = "arrow.up.arrow.down"

    public let permissions = [
        PermissionUse(.accessibility, required: true,
                      reason: "Changing scroll events before apps see them needs Accessibility. "
                            + "Scroll flips the direction and does nothing else with them."),
    ]

    public let legacyApp: LegacyApp? = LegacyApp(
        name: "Vellscroll",
        bundleID: "com.vellund.Vellscroll",
        defaultsKeys: ["vellscroll.settings"])

    public private(set) var isRunning = false

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        // Any settings change may mean the tap should start or stop.
        SettingsStore.shared.onChange = { _ in ScrollTap.shared.syncWithSettings() }
        ScrollTap.shared.syncWithSettings()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        SettingsStore.shared.onChange = nil
        // Leaving a tap installed would keep inverting scroll with the add-on
        // switched off, which looks exactly like a broken mouse.
        ScrollTap.shared.stop()
    }

    public func menuItems() -> [NSMenuItem] {
        let settings = SettingsStore.shared.settings
        let systemNatural = SystemScroll.isNaturalOn
        var items: [NSMenuItem] = []

        // Lead with what each device actually does. "Invert mouse wheel" is the
        // mechanism; people care about the outcome, and the outcome depends on
        // a system switch Scroll does not control.
        let trackpad = EffectiveDirection.resolve(source: .trackpad,
                                                  systemNatural: systemNatural, settings: settings)
        let mouse = EffectiveDirection.resolve(source: .mouse,
                                               systemNatural: systemNatural, settings: settings)
        items.append(.readout("Trackpad scrolls \(trackpad.title)"))
        items.append(.readout("Mouse scrolls \(mouse.title)"))

        if !EffectiveDirection.isConventional(systemNatural: systemNatural, settings: settings) {
            items.append(ClosureMenuItem("Use natural trackpad, classic mouse") {
                Self.applyConventional()
            })
        }

        let invert = NSMenuItem(title: "Invert Scrolling", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(ClosureMenuItem("Mouse wheel", checked: settings.invertMouse) {
            SettingsStore.shared.update { $0.invertMouse.toggle() }
        })
        submenu.addItem(ClosureMenuItem("Trackpad", checked: settings.invertTrackpad) {
            SettingsStore.shared.update { $0.invertTrackpad.toggle() }
        })
        submenu.addItem(.separator())
        submenu.addItem(ClosureMenuItem("Also invert horizontal", checked: settings.invertHorizontal) {
            SettingsStore.shared.update { $0.invertHorizontal.toggle() }
        })
        invert.submenu = submenu
        items.append(invert)
        return items
    }

    public func makeSettingsView() -> AnyView {
        AnyView(ScrollSettingsView())
    }

    public func reloadAfterImport() {
        SettingsStore.shared.reload()
    }

    public func diagnostics() -> String {
        ScrollDiagnostics.report()
    }

    /// One click back to the arrangement most people want, whichever way the
    /// system switch happens to be set.
    static func applyConventional() {
        let horizontal = SettingsStore.shared.settings.invertHorizontal
        let fixed = EffectiveDirection.conventionalSettings(
            systemNatural: SystemScroll.isNaturalOn, keepingHorizontal: horizontal)
        SettingsStore.shared.update { $0 = fixed }
    }
}

/// Scroll's Settings pane.
struct ScrollSettingsView: View {

    @State private var settings = SettingsStore.shared.settings
    @State private var systemNatural = SystemScroll.isNaturalOn

    var body: some View {
        Section {
            LabeledContent("Trackpad scrolls", value: direction(.trackpad).title)
            LabeledContent("Mouse wheel scrolls", value: direction(.mouse).title)
            if !EffectiveDirection.isConventional(systemNatural: systemNatural, settings: settings) {
                Button("Use natural trackpad, classic mouse") {
                    ScrollAddOn.applyConventional()
                    settings = SettingsStore.shared.settings
                }
            }
        } header: {
            Text("Right now")
        } footer: {
            Text("macOS natural scrolling is \(systemNatural ? "on" : "off"). Scroll only ever flips a device, so the result depends on that switch too.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Invert scrolling for") {
            Toggle("Mouse wheel", isOn: $settings.invertMouse)
            Toggle("Trackpad", isOn: $settings.invertTrackpad)
            Toggle(isOn: $settings.invertHorizontal) {
                Text("Also invert horizontal")
                Text("Left and right scrolling, for the devices ticked above.")
            }
        }
        .onChange(of: settings) { _, new in
            SettingsStore.shared.update { $0 = new }
        }
        .onAppear {
            settings = SettingsStore.shared.settings
            systemNatural = SystemScroll.isNaturalOn
        }

        Section {
            Text("A Magic Mouse scrolls by gesture, so macOS reports it like a trackpad and Scroll treats it as one. On some Macs the built-in trackpad's events never reach Scroll, so inverting the trackpad may do nothing; inverting the mouse always works.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func direction(_ source: ScrollSource) -> ScrollDirection {
        EffectiveDirection.resolve(source: source, systemNatural: systemNatural, settings: settings)
    }
}
