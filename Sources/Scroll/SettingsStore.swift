import Foundation
import ScrollCore

@MainActor
final class SettingsStore {

    static let shared = SettingsStore()

    // The key Vellscroll used, so importing its settings is a straight copy.
    private static let key = "vellscroll.settings"

    private(set) var settings: ScrollSettings {
        didSet { save(); onChange?(settings) }
    }

    /// Called whenever settings change, so the tap can be started or stopped
    /// rather than sitting in the event stream doing nothing.
    var onChange: ((ScrollSettings) -> Void)?

    private init() {
        settings = Self.read()
    }

    /// Re-read from disk, after settings were imported from Vellscroll.
    func reload() {
        settings = Self.read()
    }

    private static func read() -> ScrollSettings {
        if let data = UserDefaults.standard.data(forKey: key),
           let stored = try? JSONDecoder().decode(ScrollSettings.self, from: data) {
            return stored
        }
        return .standard
    }

    func update(_ transform: (inout ScrollSettings) -> Void) {
        var copy = settings
        transform(&copy)
        settings = copy
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
