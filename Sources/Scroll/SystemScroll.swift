import Foundation

/// Reads macOS's own "Natural scrolling" switch.
///
/// Scroll only ever *flips* a scroll event — it has no absolute direction
/// of its own — so the same settings produce opposite results depending on this
/// system switch. Reading it is what lets the menu describe what each device
/// actually does rather than what Scroll is doing to it.
enum SystemScroll {

    /// True when macOS is set to natural scrolling. Defaults to true, which is
    /// the macOS default, if the preference has never been written.
    static var isNaturalOn: Bool {
        // The global domain, not our own. Synchronise first: the user may have
        // changed it in System Settings since we last looked.
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        // Built at the call site: a stored `CFString` is not Sendable and so
        // cannot be a static constant under Swift 6.
        let value = CFPreferencesCopyAppValue(
            "com.apple.swipescrolldirection" as CFString, kCFPreferencesAnyApplication)
        if let number = value as? NSNumber { return number.boolValue }
        if let flag = value as? Bool { return flag }
        return true
    }
}
