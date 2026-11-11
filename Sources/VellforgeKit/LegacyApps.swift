import AppKit

/// One of the standalone apps Vellforge replaces: Vellsnap, Vellscroll, Vellbar.
///
/// Vellforge keeps the same settings keys the old apps used, so bringing
/// settings over is a straight copy from the old app's preferences into ours.
public struct LegacyApp: Sendable {
    public let name: String
    public let bundleID: String
    /// UserDefaults keys worth copying.
    public let defaultsKeys: [String]
    /// Files in the old app's Application Support folder worth copying.
    public let supportFiles: [String]

    public init(name: String, bundleID: String,
                defaultsKeys: [String], supportFiles: [String] = []) {
        self.name = name
        self.bundleID = bundleID
        self.defaultsKeys = defaultsKeys
        self.supportFiles = supportFiles
    }
}

/// The decisions behind importing, kept free of the file system so they can
/// be tested.
public enum LegacyImport {

    /// The old values to copy: only the listed keys, and only where Vellforge
    /// has no value of its own yet. Never overwrite something the user has
    /// already set in Vellforge.
    public static func valuesToCopy(from old: [String: Any],
                                    keys: [String],
                                    alreadySet: (String) -> Bool) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in keys where !alreadySet(key) {
            if let value = old[key] { result[key] = value }
        }
        return result
    }

    /// Only an app in an Applications folder is moved to the Bin. A copy
    /// anywhere else is most likely a build folder or a download the user is
    /// keeping on purpose, so it is quit but left where it is.
    public static func isSafeToBin(_ appURL: URL, home: URL) -> Bool {
        let path = appURL.standardizedFileURL.path
        let roots = ["/Applications/",
                     home.appendingPathComponent("Applications").standardizedFileURL.path + "/"]
        return path.hasSuffix(".app") && roots.contains { path.hasPrefix($0) }
    }
}

/// What was found of one old app on this Mac.
public struct FoundLegacyApp: Identifiable {
    public let app: LegacyApp
    /// Where Launch Services thinks the app is, if anywhere.
    public let url: URL?
    public let version: String?
    public let hasSettings: Bool
    public let isRunning: Bool
    public let canMoveToBin: Bool

    public var id: String { app.bundleID }
}

@MainActor
public enum LegacyApps {

    public static func isRunning(_ app: LegacyApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    /// Old apps that are installed, running, or have left settings behind.
    public static func find(_ apps: [LegacyApp]) -> [FoundLegacyApp] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return apps.compactMap { app in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
            let settings = !readOldValues(app).isEmpty || hasSupportFiles(app)
            let running = isRunning(app)
            guard url != nil || settings || running else { return nil }
            let version = url.flatMap { Bundle(url: $0)?
                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
            return FoundLegacyApp(app: app, url: url, version: version,
                                  hasSettings: settings, isRunning: running,
                                  canMoveToBin: url.map { LegacyImport.isSafeToBin($0, home: home) } ?? false)
        }
    }

    /// Copy settings and files across. Returns how many things were copied.
    @discardableResult
    public static func importSettings(from app: LegacyApp,
                                      into defaults: UserDefaults = .standard) -> Int {
        let values = LegacyImport.valuesToCopy(from: readOldValues(app),
                                               keys: app.defaultsKeys,
                                               alreadySet: { defaults.object(forKey: $0) != nil })
        for (key, value) in values { defaults.set(value, forKey: key) }

        var files = 0
        if let from = supportDirectory(for: app.bundleID),
           let ownID = Bundle.main.bundleIdentifier,
           let to = supportDirectory(for: ownID) {
            try? FileManager.default.createDirectory(at: to, withIntermediateDirectories: true)
            for name in app.supportFiles {
                let source = from.appendingPathComponent(name)
                let target = to.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: source.path),
                      !FileManager.default.fileExists(atPath: target.path) else { continue }
                if (try? FileManager.default.copyItem(at: source, to: target)) != nil { files += 1 }
            }
        }
        return values.count + files
    }

    /// Ask the old app to quit, and wait briefly for it to go.
    public static func quit(_ app: LegacyApp) async {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        for instance in running { instance.terminate() }
        for _ in 0..<30 {
            if running.allSatisfy(\.isTerminated) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    public static func moveToBin(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle([url]) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    // MARK: Reading the old app's preferences

    private static func readOldValues(_ app: LegacyApp) -> [String: Any] {
        let domain = app.bundleID as CFString
        CFPreferencesAppSynchronize(domain)
        var values: [String: Any] = [:]
        for key in app.defaultsKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, domain) {
                values[key] = value
            }
        }
        return values
    }

    private static func hasSupportFiles(_ app: LegacyApp) -> Bool {
        guard let dir = supportDirectory(for: app.bundleID) else { return false }
        return app.supportFiles.contains {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
    }

    private static func supportDirectory(for bundleID: String) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(bundleID, isDirectory: true)
    }
}
