import AppKit
import VellforgeKit
import ApplicationServices
import SnapCore

struct RestoreSummary {
    let applied: Int
    let total: Int
    let launched: [String]

    var message: String {
        if applied == total, launched.isEmpty {
            return "Restored \(applied) window\(applied == 1 ? "" : "s")."
        }
        var parts = ["Restored \(applied) of \(total) windows."]
        if !launched.isEmpty { parts.append("Opening \(launched.count) app\(launched.count == 1 ? "" : "s").") }
        return parts.joined(separator: " ")
    }
}

/// Captures and restores whole-desktop arrangements.
@MainActor
final class LayoutStore {

    static let shared = LayoutStore()

    private(set) var layouts: [SavedLayout] = []

    private init() { load() }

    /// Re-read from disk, after layouts were imported from Vellsnap.
    func reload() { load() }

    // MARK: Capture

    func capture(named name: String) -> SavedLayout? {
        guard AccessibilityPermission.isTrusted else { return nil }

        let displays = ScreenBridge.displays()
        let primaryMaxY = ScreenBridge.primaryMaxY
        var snapshots: [WindowSnapshot] = []

        for live in WindowController.allWindows() {
            guard let axFrame = WindowController.frame(of: live.element) else { continue }
            let appKit = CoordinateSpace.toAppKit(axFrame, primaryMaxY: primaryMaxY)
            guard let display = displays.containing(
                CGPoint(x: appKit.midX, y: appKit.midY)) else { continue }

            snapshots.append(WindowSnapshot(
                bundleID: live.bundleID,
                title: live.title,
                axIndex: live.axIndex,
                displayID: display.id,
                zone: Zone(rect: appKit, in: display.visibleFrame)))
        }

        guard !snapshots.isEmpty else { return nil }

        let layout = SavedLayout(id: UUID().uuidString,
                                 name: name,
                                 windows: snapshots,
                                 createdAt: Date())
        layouts.append(layout)
        save()
        return layout
    }

    // MARK: Restore

    @discardableResult
    func restore(_ layout: SavedLayout, relaunchMissing: Bool = false) -> RestoreSummary {
        let live = WindowController.allWindows()
        let candidates = live.map {
            MatchCandidate(bundleID: $0.bundleID, title: $0.title, axIndex: $0.axIndex)
        }
        let matches = WindowMatcher.match(snapshots: layout.windows, candidates: candidates)

        let displays = ScreenBridge.displays()
        let primaryMaxY = ScreenBridge.primaryMaxY
        var applied = 0

        for (snapshotIndex, candidateIndex) in matches {
            let snapshot = layout.windows[snapshotIndex]
            let window = live[candidateIndex].element

            // Prefer the display the window was captured on. If that monitor is
            // no longer attached, fall back to the primary rather than placing
            // the window off-screen.
            let display = displays.first { $0.id == snapshot.displayID } ?? displays.first
            guard let display else { continue }

            let rect = snapshot.zone.resolve(in: display.visibleFrame)
            let axRect = CoordinateSpace.toAccessibility(rect, primaryMaxY: primaryMaxY)
            if WindowController.setFrame(axRect, of: window) { applied += 1 }
        }

        var launched: [String] = []
        if relaunchMissing {
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            for bundleID in layout.referencedApps.subtracting(running).sorted() {
                guard let url = NSWorkspace.shared
                    .urlForApplication(withBundleIdentifier: bundleID) else { continue }
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
                launched.append(bundleID)
            }
        }

        return RestoreSummary(applied: applied,
                              total: layout.windows.count,
                              launched: launched)
    }

    // MARK: Mutation

    func delete(id: String) {
        layouts.removeAll { $0.id == id }
        save()
    }

    func rename(id: String, to name: String) {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { return }
        layouts[index].name = name
        save()
    }

    /// Overwrite an existing layout with the current arrangement.
    func update(id: String) {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { return }
        let name = layouts[index].name
        layouts.remove(at: index)
        guard let fresh = capture(named: name) else { return }
        // `capture` appended it; move it back to its original position.
        layouts.removeLast()
        layouts.insert(fresh, at: index)
        save()
    }

    // MARK: Persistence

    private var storeURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let directory = base.appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("layouts.json")
    }

    private func load() {
        guard let url = storeURL, let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        layouts = (try? decoder.decode([SavedLayout].self, from: data)) ?? []
    }

    private func save() {
        guard let url = storeURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Readable on purpose: a layouts file the user can open and inspect is
        // easier to trust than an opaque blob.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(layouts) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
