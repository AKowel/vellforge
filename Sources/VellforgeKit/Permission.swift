import AppKit
import ApplicationServices
import CoreGraphics
import Observation

/// The macOS privacy permissions an add-on can ask for.
///
/// Permissions belong to the app, not to an add-on: macOS identifies an app by
/// its code signature, so one Accessibility grant covers every add-on that uses
/// it. Each add-on declares what it needs, and the app asks only when an add-on
/// that needs something is switched on.
public enum Permission: String, CaseIterable, Sendable, Identifiable {
    case accessibility
    case screenRecording

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accessibility:   return "Accessibility"
        case .screenRecording: return "Screen Recording"
        }
    }

    /// macOS applies a new Screen Recording grant only after the app restarts.
    public var needsRelaunchAfterGrant: Bool { self == .screenRecording }

    @MainActor public var isGranted: Bool {
        switch self {
        case .accessibility:   return AccessibilityPermission.isTrusted
        case .screenRecording: return ScreenRecordingPermission.isGranted
        }
    }

    /// Shows the system prompt the first time. Afterwards macOS stays silent,
    /// so callers also open System Settings.
    @MainActor public func request() {
        switch self {
        case .accessibility:   AccessibilityPermission.promptIfNeeded()
        case .screenRecording: ScreenRecordingPermission.request()
        }
    }

    @MainActor public func openSystemSettings() {
        let anchor: String
        switch self {
        case .accessibility:   anchor = "Privacy_Accessibility"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        }
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Prompt, and open the right list in System Settings for the second visit.
    @MainActor public func requestAndOpenSettings() {
        request()
        openSystemSettings()
    }
}

/// How one add-on uses one permission, in words a person can judge.
public struct PermissionUse: Sendable, Identifiable {
    public let permission: Permission
    /// Required means the add-on does nothing without it. Optional ones only
    /// add to what it does.
    public let isRequired: Bool
    public let reason: String

    public var id: String { permission.rawValue }

    public init(_ permission: Permission, required: Bool, reason: String) {
        self.permission = permission
        self.isRequired = required
        self.reason = reason
    }
}

/// Accessibility: needed to move other apps' windows, change input events, or
/// read the menu bar's contents.
@MainActor
public enum AccessibilityPermission {

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt if access has not been granted yet. Returns the
    /// state at the time of the call: granting is asynchronous, so `false` does
    /// not mean the user refused.
    @discardableResult
    public static func promptIfNeeded() -> Bool {
        // The imported `kAXTrustedCheckOptionPrompt` is a mutable global and so
        // is rejected under Swift 6 strict concurrency. Its value is a stable,
        // documented string, so use that directly.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public static func openSystemSettings() {
        Permission.accessibility.openSystemSettings()
    }
}

/// Screen Recording: the only way to see other apps' menu bar icons.
@MainActor
public enum ScreenRecordingPermission {

    public static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Triggers the system prompt. The grant only takes effect after the app is
    /// relaunched, which macOS enforces.
    @discardableResult
    public static func request() -> Bool { CGRequestScreenCaptureAccess() }

    public static func openSystemSettings() {
        Permission.screenRecording.openSystemSettings()
    }
}

/// Watches the permission state, so the app reacts when a grant arrives.
///
/// macOS sends no notification when the user flips a switch in System
/// Settings, so the only option is to look. Both checks are cheap local calls.
@MainActor
@Observable
public final class PermissionMonitor {

    public static let shared = PermissionMonitor()

    public private(set) var granted: Set<Permission> = []

    /// Called after any change, grant or revoke.
    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?

    private init() {
        granted = Self.read()
    }

    public func isGranted(_ permission: Permission) -> Bool {
        granted.contains(permission)
    }

    public func start(interval: Duration = .seconds(2)) {
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.check()
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Check now, rather than waiting for the next tick.
    public func check() {
        let now = Self.read()
        guard now != granted else { return }
        granted = now
        onChange?()
    }

    private static func read() -> Set<Permission> {
        Set(Permission.allCases.filter { $0.isGranted })
    }
}
