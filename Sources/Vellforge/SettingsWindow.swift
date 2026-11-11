import AppKit
import Observation
import SwiftUI
import VellforgeKit

@MainActor
@Observable
final class SettingsNavigation {
    var selection: String? = "general"
}

@MainActor
final class SettingsWindowController: NSWindowController {

    private let navigation = SettingsNavigation()

    init(app: AppDelegate) {
        let root = SettingsView(app: app, navigation: navigation)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Vellforge Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 780, height: 560))
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("vellforge.settings")
        if window.frameAutosaveName.isEmpty || !window.setFrameUsingName("vellforge.settings") {
            window.center()
        }
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(pane: String?) {
        if let pane { navigation.selection = pane }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Root

struct SettingsView: View {

    let app: AppDelegate
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                Label("General", systemImage: "gearshape").tag("general")
                Section("Add-ons") {
                    ForEach(app.registry.addOns, id: \.id) { addOn in
                        Label(addOn.name, systemImage: addOn.symbolName).tag(addOn.id)
                    }
                }
                Label("About", systemImage: "info.circle").tag("about")
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
    }

    @ViewBuilder private var detail: some View {
        switch navigation.selection {
        case "about":
            AboutPane()
        case let id? where app.registry.addOn(id: id) != nil:
            AddOnPane(app: app, addOn: app.registry.addOn(id: id)!)
                .id(id)
        default:
            GeneralPane(app: app, navigation: navigation)
        }
    }
}

// MARK: - General

struct GeneralPane: View {

    let app: AppDelegate
    let navigation: SettingsNavigation

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var autoUpdate = false

    var body: some View {
        let registry = app.registry
        Form {
            Section {
                ForEach(registry.addOns, id: \.id) { addOn in
                    Toggle(isOn: Binding(
                        get: { registry.isEnabled(addOn) },
                        set: { app.enable(addOn, $0) }
                    )) {
                        Label {
                            Text(addOn.name)
                            Text(statusLine(for: addOn))
                        } icon: {
                            Image(systemName: addOn.symbolName)
                        }
                    }
                }
            } header: {
                Text("Add-ons")
            } footer: {
                Text("Switch on the tools you want. Each has its own page on the left.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            let inUse = registry.permissionsInUse()
            if !inUse.isEmpty {
                Section {
                    ForEach(inUse, id: \.permission) { entry in
                        PermissionRowView(
                            permission: entry.permission,
                            reason: "Used by " + ListFormatter.localizedString(
                                byJoining: entry.users.map(\.name)) + ".",
                            isRequired: entry.users.contains { addOn in
                                addOn.requiredPermissions.contains(entry.permission)
                            })
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    Text("One grant covers every add-on that uses it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("General") {
                Toggle("Launch Vellforge at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        if !LaunchAtLogin.set(on) { launchAtLogin = LaunchAtLogin.isEnabled }
                    }
                Toggle("Check for updates automatically", isOn: $autoUpdate)
                    .disabled(!app.updater.isAvailable)
                    .onChange(of: autoUpdate) { _, on in app.updater.automaticallyChecks = on }
                LabeledContent("Version \(AppInfo.version)") {
                    Button("Check for Updates…") { app.updater.checkForUpdates() }
                        .disabled(!app.updater.isAvailable)
                }
                if !app.updater.isAvailable {
                    Text("Updates are off in this build: it has no update key.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Coming from Vellsnap, Vellscroll or Vellbar?") {
                HStack {
                    Text("Vellforge replaces all three. It can copy their settings and tidy the old apps away.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Bring Settings Over…") { app.showWelcome() }
                }
            }

            Section {
                HStack {
                    Button("Diagnostics…") { app.showDiagnostics() }
                    Spacer()
                    Link("Help", destination: Links.docs)
                    Link("Website", destination: Links.site)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            autoUpdate = app.updater.automaticallyChecks
        }
    }

    private func statusLine(for addOn: any AddOn) -> String {
        statusText(for: addOn, registry: app.registry, off: addOn.tagline)
    }
}

/// "On", "Off", or what it is waiting for. Reads the permission monitor so the
/// line updates the moment a grant arrives.
@MainActor
func statusText(for addOn: any AddOn, registry: AddOnRegistry, off: String) -> String {
    guard registry.isEnabled(addOn) else { return off }
    let missing = addOn.requiredPermissions.filter { !PermissionMonitor.shared.isGranted($0) }
    if missing.isEmpty { return "On · " + addOn.tagline }
    return "Waiting for " + missing.map(\.title).joined(separator: " and ") + " access"
}

// MARK: - One add-on

struct AddOnPane: View {

    let app: AppDelegate
    let addOn: any AddOn

    @State private var legacyRunning = false

    var body: some View {
        let registry = app.registry
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { registry.isEnabled(addOn) },
                    set: { app.enable(addOn, $0) }
                )) {
                    Text(addOn.name).font(.headline)
                    Text(addOn.summary)
                }
                Text(statusText(for: addOn, registry: registry,
                                off: "Off. Switch it on to use \(addOn.name)."))
                    .font(.callout).foregroundStyle(.secondary)

                if legacyRunning, let legacy = addOn.legacyApp {
                    HStack {
                        Label("\(legacy.name) is still running. Quit it so the two don't fight.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Quit \(legacy.name)") {
                            Task {
                                await LegacyApps.quit(legacy)
                                legacyRunning = LegacyApps.isRunning(legacy)
                            }
                        }
                    }
                }
            }

            if !addOn.permissions.isEmpty {
                Section("Permissions") {
                    ForEach(addOn.permissions) { use in
                        PermissionRowView(use)
                    }
                }
            }

            addOn.makeSettingsView()

            Section {
                HStack {
                    Button("Diagnostics…") {
                        DiagnosticsWindow.show(title: "\(addOn.name) diagnostics",
                                               report: addOn.diagnostics())
                    }
                    Spacer()
                    Link("\(addOn.name) help", destination: Links.docs(for: addOn.id))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(addOn.name)
        .onAppear {
            legacyRunning = addOn.legacyApp.map(LegacyApps.isRunning) ?? false
        }
    }
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Vellforge").font(.largeTitle.bold())
            Text("Version \(AppInfo.version) (\(AppInfo.build))")
                .foregroundStyle(.secondary)
            Text("Small tools for macOS, built properly. Free and open source: no account, no telemetry.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Text("Vellforge brings together what used to be Vellsnap, Vellscroll and Vellbar. Part of Vellund.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: 16) {
                Link("Website", destination: Links.site)
                Link("Source code", destination: Links.source)
                Link("Support Vellforge", destination: Links.donate)
            }
            Text("MIT licence · © Vellund")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }
}
