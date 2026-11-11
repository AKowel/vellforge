import Foundation
import Observation

/// Owns the list of add-ons and decides which of them should be running.
///
/// An add-on runs when it is switched on *and* every permission it requires is
/// granted. `refresh()` brings reality in line with that rule, and is called
/// whenever either side changes: a switch in Settings, a grant arriving from
/// System Settings, an old standalone app quitting.
@MainActor
@Observable
public final class AddOnRegistry {

    public static let enabledKey = "vellforge.enabledAddOns"

    public let addOns: [any AddOn]

    public private(set) var enabledIDs: Set<String>

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isGranted: @MainActor (Permission) -> Bool

    public init(addOns: [any AddOn],
                defaults: UserDefaults = .standard,
                isGranted: @escaping @MainActor (Permission) -> Bool = { $0.isGranted }) {
        self.addOns = addOns
        self.defaults = defaults
        self.isGranted = isGranted
        let stored = defaults.stringArray(forKey: Self.enabledKey) ?? []
        // Ignore ids of add-ons that no longer exist.
        let known = Set(addOns.map(\.id))
        enabledIDs = Set(stored).intersection(known)
    }

    public func addOn(id: String) -> (any AddOn)? {
        addOns.first { $0.id == id }
    }

    public func isEnabled(_ addOn: any AddOn) -> Bool {
        enabledIDs.contains(addOn.id)
    }

    public var enabledAddOns: [any AddOn] {
        addOns.filter { isEnabled($0) }
    }

    public func setEnabled(_ enabled: Bool, for addOn: any AddOn) {
        if enabled { enabledIDs.insert(addOn.id) } else { enabledIDs.remove(addOn.id) }
        // Stored in the order add-ons are listed, so the file reads sensibly.
        defaults.set(addOns.map(\.id).filter { enabledIDs.contains($0) },
                     forKey: Self.enabledKey)
        refresh()
    }

    /// Required permissions that are not granted yet.
    public func missingPermissions(for addOn: any AddOn) -> [Permission] {
        addOn.requiredPermissions.filter { !isGranted($0) }
    }

    /// Whether the add-on should be running right now.
    public func shouldRun(_ addOn: any AddOn) -> Bool {
        isEnabled(addOn) && missingPermissions(for: addOn).isEmpty
    }

    /// Start what should run, stop what shouldn't.
    public func refresh() {
        for addOn in addOns {
            let want = shouldRun(addOn)
            if want && !addOn.isRunning {
                addOn.start()
            } else if !want && addOn.isRunning {
                addOn.stop()
            }
        }
    }

    /// Stop and start again, for when something outside changed underneath an
    /// add-on (an old app that held its shortcuts has just quit).
    public func restart(_ addOn: any AddOn) {
        guard addOn.isRunning else { refresh(); return }
        addOn.stop()
        refresh()
    }

    public func stopAll() {
        for addOn in addOns where addOn.isRunning { addOn.stop() }
    }

    /// Every permission any switched-on add-on uses, with who uses it.
    public func permissionsInUse() -> [(permission: Permission, users: [any AddOn])] {
        Permission.allCases.compactMap { permission in
            let users = enabledAddOns.filter { addOn in
                addOn.permissions.contains { $0.permission == permission }
            }
            return users.isEmpty ? nil : (permission, users)
        }
    }
}
