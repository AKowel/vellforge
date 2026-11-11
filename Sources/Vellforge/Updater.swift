import AppKit
import Sparkle

/// Sparkle, for updates from GitHub Releases.
///
/// The feed is `SUFeedURL` in Info.plist (vellforge.com/appcast.xml, which the
/// site redirects to the newest release's appcast). Sparkle only fetches that
/// file; no system profile is ever sent. Updates are verified against
/// `SUPublicEDKey`, so a build without a key, such as a local debug build,
/// leaves the updater off rather than showing Sparkle's start-up error.
@MainActor
final class Updater: NSObject {

    private var controller: SPUStandardUpdaterController?

    /// A scheduled check found an update the user hasn't looked at yet.
    private(set) var updateIsWaiting = false

    var isAvailable: Bool { controller != nil }

    override init() {
        super.init()
        let info = Bundle.main.infoDictionary ?? [:]
        let key = info["SUPublicEDKey"] as? String ?? ""
        let feed = info["SUFeedURL"] as? String ?? ""
        guard !key.isEmpty, !feed.isEmpty else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: self)
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}

// Sparkle calls its user driver delegate on the main thread.
extension Updater: @preconcurrency SPUStandardUserDriverDelegate {

    /// Vellforge lives in the menu bar, so an update window popping up over
    /// whatever the user is doing would be rude. Sparkle shows it gently and
    /// the menu gets an "Update Available…" row.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if !state.userInitiated { updateIsWaiting = true }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateIsWaiting = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        updateIsWaiting = false
    }
}
