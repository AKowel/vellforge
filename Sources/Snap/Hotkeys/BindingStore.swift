import AppKit

/// Owns the command-to-shortcut map, persists it, and keeps the live hotkey
/// registrations in sync with it.
@MainActor
final class BindingStore {

    static let shared = BindingStore()

    private let defaultsKey = "vellsnap.bindings"
    private(set) var bindings: [Command: KeyBinding] = [:]
    /// Commands whose shortcut failed to register — almost always because
    /// something else on the system already owns that combination.
    private(set) var conflicted: Set<Command> = []

    /// Set by the add-on while Snap is running. Rebinding a shortcut in
    /// Settings must not register hotkeys while Snap itself is switched off.
    var isActive = false

    private init() {
        load()
    }

    /// Re-read from disk, after settings were imported from Vellsnap.
    func reload() {
        load()
        reregister()
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode([String: KeyBinding].self, from: data)
        else {
            bindings = Self.defaults()
            return
        }
        // Start from defaults so commands added in a later version still get
        // their shortcut, then let stored values win.
        var merged = Self.defaults()
        for (key, value) in stored {
            guard let command = Command(rawValue: key) else { continue }
            merged[command] = value
        }
        bindings = merged
    }

    private func save() {
        let encodable = Dictionary(uniqueKeysWithValues:
            bindings.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private static func defaults() -> [Command: KeyBinding] {
        var map: [Command: KeyBinding] = [:]
        for command in Command.allCases {
            if let binding = command.defaultBinding { map[command] = binding }
        }
        return map
    }

    // MARK: Mutation

    func set(_ binding: KeyBinding?, for command: Command) {
        if let binding { bindings[command] = binding } else { bindings.removeValue(forKey: command) }
        save()
        reregister()
    }

    func resetToDefaults() {
        bindings = Self.defaults()
        save()
        reregister()
    }

    /// The command already using `binding`, if any — so the recorder can warn
    /// rather than silently stealing a shortcut.
    func command(using binding: KeyBinding, excluding command: Command) -> Command? {
        bindings.first { $0.key != command && $0.value == binding }?.key
    }

    // MARK: Registration

    func reregister() {
        HotKeyManager.shared.unregisterAll()
        conflicted.removeAll()
        guard isActive else { return }

        for (command, binding) in bindings {
            let ok = HotKeyManager.shared.register(binding) {
                CommandRunner.run(command)
            }
            if !ok { conflicted.insert(command) }
        }
    }
}
