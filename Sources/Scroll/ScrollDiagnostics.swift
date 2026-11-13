import AppKit
import VellforgeKit
import CoreGraphics
import IOKit.hid
import ScrollCore

/// Reports whether Scroll is actually doing anything.
///
/// Every failure here is silent by nature: a missing permission, a refused
/// event tap, or a system setting that makes the configuration a no-op all look
/// identical from the outside — scrolling simply behaves normally.
@MainActor
enum ScrollDiagnostics {

    static func report() -> String {
        var out: [String] = []
        func line(_ s: String) { out.append(s) }

        let settings = SettingsStore.shared.settings
        let systemNatural = SystemScroll.isNaturalOn

        line("SCROLL")
        line("PERMISSION")
        line("  Accessibility:    \(AccessibilityPermission.isTrusted ? "granted" : "NOT granted")")
        // Event taps that observe input often require Input Monitoring as well
        // as Accessibility, and the two are separate lists in System Settings.
        let listen = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let listenName: String
        switch listen {
        case kIOHIDAccessTypeGranted: listenName = "granted"
        case kIOHIDAccessTypeDenied:  listenName = "DENIED"
        default:                      listenName = "not yet requested"
        }
        line("  Input Monitoring: \(listenName)")
        line("    (without it the event tap cannot be created at all)")
        line("")
        line("SETTINGS")
        line("  invert mouse:      \(settings.invertMouse)")
        line("  invert trackpad:   \(settings.invertTrackpad)")
        line("  invert horizontal: \(settings.invertHorizontal)")
        line("  is no-op:          \(settings.isNoOp)")
        line("")
        line("SYSTEM")
        line("  macOS natural scrolling: \(systemNatural ? "ON" : "OFF")")
        line("")
        line("EFFECTIVE RESULT")
        line("  trackpad scrolls: \(EffectiveDirection.resolve(source: .trackpad, systemNatural: systemNatural, settings: settings).title)")
        line("  mouse scrolls:    \(EffectiveDirection.resolve(source: .mouse, systemNatural: systemNatural, settings: settings).title)")
        line("")
        line("EVENT TAP")
        line("  created: \(ScrollTap.shared.isRunning)")
        line("  enabled: \(ScrollTap.shared.isEnabled)")
        let c = ScrollTap.shared.eventCounts
        line("  scroll events seen:    \(c.seen)")
        line("  events actually flipped: \(c.flipped)")
        let h0 = ScrollTap.shared.health
        let judged = ScrollTap.shared.lastSource.map { $0 == .trackpad ? "trackpad" : "mouse" } ?? "none yet"
        line("  last event was:        \(c.lastContinuous ? "continuous" : "discrete"), phase \(h0.phase), momentum \(h0.momentum) -> \(judged)")
        let d = ScrollTap.shared.lastDeltas
        line("  last event line delta:  \(d.lineIn) -> \(d.lineOut)")
        line("  last event point delta: \(d.pointIn) -> \(d.pointOut)")
        if d.lineIn != 0 && (d.lineIn == d.lineOut || d.pointIn == d.pointOut) {
            line("  -> WARNING: a delta was not actually inverted")
        }
        let h = ScrollTap.shared.health
        line("  disabled by timeout:    \(h.timeouts)   <- each one is a visible stall")
        line("  disabled by user input: \(h.userInput)")
        line("  last scroll phase:      \(h.phase)")
        line("  last momentum phase:    \(h.momentum)")
        let pd = ScrollTap.shared.perDevice
        line("  judged trackpad: \(pd.trackpad)")
        line("  judged mouse:    \(pd.mouse)")
        if pd.trackpad == 0 && pd.mouse > 0 {
            line("  -> NO trackpad events have reached the tap at all")
        }
        line("")
        line("DEVICE SWITCHES (the gap is the stall)")
        let t = ScrollTap.shared.transitions
        if t.isEmpty { line("  none recorded yet") }
        for e in t { line("  \(e)") }
        line("")
        line("RECENT EVENTS (oldest first)")
        for e in ScrollTap.shared.recentEvents { line("  \(e)") }
        if c.seen == 0 && ScrollTap.shared.isRunning {
            line("  -> tap is installed but no scroll events reached it")
        }
        if !ScrollTap.shared.isRunning {
            line("  -> NOT INTERCEPTING. Causes, in order of likelihood:")
            line("     1. Accessibility not granted to THIS bundle")
            line("     2. Both invert switches off (nothing to do)")
            line("     3. CGEvent.tapCreate refused")
        }

        return out.joined(separator: "\n")
    }
}
