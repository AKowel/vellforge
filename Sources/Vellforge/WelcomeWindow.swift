import AppKit
import Observation
import SwiftUI
import VellforgeKit

/// First launch: pick add-ons, bring settings over from the old standalone
/// apps, then grant whatever the chosen add-ons need. Also reachable later
/// from Settings, for anyone who installs Vellforge before removing the old
/// apps.
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {

    private let onClose: () -> Void

    init(app: AppDelegate, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let model = WelcomeModel(app: app)
        let hosting = NSHostingController(rootView: WelcomeView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Vellforge"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        model.close = { [weak self] in self?.close() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        guard let window else { return }
        if !window.isVisible { WindowPlacement.centerOnActiveScreen(window) }
        showWindow(nil)
        WindowPlacement.bringToFront(window)
    }

    func windowWillClose(_ notification: Notification) {
        // Closing early still counts as seen: the menu offers "Choose
        // Add-ons…" for anyone who skipped it.
        UserDefaults.standard.set(true, forKey: AppDelegate.welcomeDoneKey)
        onClose()
    }
}

@MainActor
@Observable
final class WelcomeModel {

    enum Step { case choose, permissions }

    let app: AppDelegate
    var step = Step.choose
    var chosen: Set<String>
    let found: [FoundLegacyApp]
    var importing: Set<String>
    var autoUpdate = true
    var working = false
    @ObservationIgnored var close: () -> Void = {}

    init(app: AppDelegate) {
        self.app = app
        let legacy = app.registry.addOns.compactMap(\.legacyApp)
        found = LegacyApps.find(legacy)
        importing = Set(found.filter(\.hasWork).map(\.id))

        // Pre-tick what is already on, plus whatever the old apps were doing.
        var chosen = app.registry.enabledIDs
        for addOn in app.registry.addOns
        where found.contains(where: { $0.id == addOn.legacyApp?.bundleID }) {
            chosen.insert(addOn.id)
        }
        self.chosen = chosen
    }

    var chosenAddOns: [any AddOn] {
        app.registry.addOns.filter { chosen.contains($0.id) }
    }

    /// Permissions the chosen add-ons use, each with every reason for it.
    var permissionRows: [(use: PermissionUse, key: String)] {
        Permission.allCases.compactMap { permission in
            let uses = chosenAddOns.compactMap { addOn in
                addOn.permissions.first { $0.permission == permission }.map { (addOn, $0) }
            }
            guard !uses.isEmpty else { return nil }
            let reason = uses.map { "\($0.0.name): \($0.1.reason)" }.joined(separator: "\n\n")
            let required = uses.contains { $0.1.isRequired }
            return (PermissionUse(permission, required: required, reason: reason), permission.id)
        }
    }

    func finishChoosing() async {
        working = true
        defer { working = false }

        // Old apps first: their settings must be in place before an add-on
        // starts, and Vellsnap must have let go of its shortcuts.
        var imported: Set<String> = []
        for item in found where importing.contains(item.id) {
            if item.isRunning { await LegacyApps.quit(item.app) }
            LegacyApps.importSettings(from: item.app)
            if item.canMoveToBin, let url = item.url { _ = await LegacyApps.moveToBin(url) }
            imported.insert(item.id)
        }
        for addOn in app.registry.addOns
        where imported.contains(addOn.legacyApp?.bundleID ?? "") {
            addOn.reloadAfterImport()
        }

        if app.updater.isAvailable { app.updater.automaticallyChecks = autoUpdate }
        for addOn in app.registry.addOns {
            app.registry.setEnabled(chosen.contains(addOn.id), for: addOn)
        }
        UserDefaults.standard.set(true, forKey: AppDelegate.welcomeDoneKey)

        let needsAnything = permissionRows.contains { !$0.use.permission.isGranted }
        if needsAnything {
            step = .permissions
            // Ask for the first required one straight away: it is what the
            // user just agreed to by choosing the add-on.
            if let first = chosenAddOns.flatMap({ app.registry.missingPermissions(for: $0) }).first {
                first.request()
            }
        } else {
            close()
        }
    }
}

struct WelcomeView: View {

    @Bindable var model: WelcomeModel

    var body: some View {
        // A fixed height with the middle scrolling, so the buttons are always
        // on screen, even on a small display with every old app found.
        VStack(alignment: .leading, spacing: 0) {
            switch model.step {
            case .choose: choose
            case .permissions: permissions
            }
        }
        .frame(width: 580, height: 620)
    }

    private func page<Middle: View, Footer: View>(
        @ViewBuilder header: () -> some View,
        @ViewBuilder middle: () -> Middle,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .padding(.bottom, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) { middle() }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 16)
            }
            Divider()
            HStack { footer() }
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
        }
    }

    // MARK: Step 1

    private var choose: some View {
        page {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Vellforge").font(.title.bold())
                    Text("Small tools for your Mac. Switch on the ones you want; you can change this any time in Settings.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } middle: {
            ForEach(model.app.registry.addOns, id: \.id) { addOn in
                AddOnChoice(addOn: addOn, isOn: Binding(
                    get: { model.chosen.contains(addOn.id) },
                    set: { on in
                        if on { model.chosen.insert(addOn.id) } else { model.chosen.remove(addOn.id) }
                    }))
            }
            if !model.found.isEmpty { oldApps }
            WhereItLives()
        } footer: {
            if model.app.updater.isAvailable {
                Toggle("Check for updates automatically", isOn: $model.autoUpdate)
            }
            Spacer()
            if model.working { ProgressView().controlSize(.small) }
            Button("Continue") { Task { await model.finishChoosing() } }
                .keyboardShortcut(.defaultAction)
                .disabled(model.working)
        }
    }

    private var oldApps: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Vellforge replaces these. Tick one to copy its settings across and put the old app away.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(model.found) { item in
                    let title = item.app.name + (item.version.map { " \($0)" } ?? "")
                    if item.hasWork {
                        Toggle(isOn: Binding(
                            get: { model.importing.contains(item.id) },
                            set: { on in
                                if on { model.importing.insert(item.id) } else { model.importing.remove(item.id) }
                            })) {
                            Text(title)
                            Text(plan(for: item)).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        // Nothing to copy, nothing to quit, nothing safe to bin:
                        // a tick box here would promise something it can't do.
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                            Text(plan(for: item)).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.leading, 22)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Text("Found the old apps").fontWeight(.medium)
        }
    }

    private func plan(for item: FoundLegacyApp) -> String {
        var steps: [String] = []
        if item.hasSettings { steps.append("copies its settings") }
        if item.isRunning { steps.append("quits it") }
        if item.canMoveToBin { steps.append("moves it to the Bin") }
        var text = ListFormatter.localizedString(byJoining: steps)
        text = text.isEmpty ? "No settings to copy." : text.prefix(1).uppercased() + text.dropFirst() + "."
        if !item.canMoveToBin, let url = item.url {
            text += " The copy in \(url.deletingLastPathComponent().path) stays where it is."
        }
        return text
    }

    // MARK: Step 2

    private var permissions: some View {
        page {
            VStack(alignment: .leading, spacing: 6) {
                Text("One more step").font(.title.bold())
                Text("macOS asks you to allow these in System Settings. One grant covers every add-on that uses it, and this window updates as soon as you do.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } middle: {
            ForEach(model.permissionRows, id: \.key) { row in
                PermissionRowView(row.use)
                Divider()
            }
            WhereItLives()
        } footer: {
            Spacer()
            let ready = model.permissionRows.allSatisfy {
                !$0.use.isRequired || PermissionMonitor.shared.isGranted($0.use.permission)
            }
            Button(ready ? "Done" : "Finish Later") { model.close() }
                .keyboardShortcut(.defaultAction)
        }
    }
}

extension FoundLegacyApp {
    /// Whether importing it would actually do anything.
    var hasWork: Bool { hasSettings || isRunning || canMoveToBin }
}

/// A menu bar app is easy to lose: on a full menu bar macOS hides the newest
/// icons behind the camera notch, with no sign that it has.
private struct WhereItLives: View {
    var body: some View {
        Label("Vellforge lives in your menu bar. If the bar is full, macOS can hide new icons behind the camera notch: open Vellforge again from Finder or Spotlight to get Settings, or switch on Bar to make room.",
              systemImage: "menubar.arrow.up.rectangle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}

private struct AddOnChoice: View {
    let addOn: any AddOn
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: addOn.symbolName)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(addOn.name).font(.headline)
                Text(addOn.summary)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(permissionNote).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden()
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var permissionNote: String {
        let required = addOn.permissions.filter(\.isRequired).map(\.permission.title)
        let optional = addOn.permissions.filter { !$0.isRequired }.map(\.permission.title)
        if !required.isEmpty { return "Needs " + required.joined(separator: " and ") }
        if !optional.isEmpty {
            return "No permissions needed. " + optional.joined(separator: " and ")
                + (optional.count == 1 ? " adds" : " add") + " extras."
        }
        return "No permissions needed"
    }
}
