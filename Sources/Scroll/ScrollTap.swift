import AppKit
import VellforgeKit
import CoreGraphics
import os
import ScrollCore

/// Intercepts scroll events and flips them for the devices the user chose.
///
/// A `CGEvent` tap rather than a passive monitor, because this has to *change*
/// events, not just watch them — which means a `.defaultTap`, and Accessibility
/// permission.
///
/// The callback deliberately does **not** hop to the main actor. Scroll events
/// arrive in a dense stream, and queueing each one behind whatever the UI is
/// doing would add latency to every scroll and risk the system disabling the
/// tap for being slow. Instead the settings it needs are published into a lock
/// the callback can read directly.
@MainActor
final class ScrollTap {

    static let shared = ScrollTap()
    private init() {}

    private var source: CFRunLoopSource?

    var isRunning: Bool { TapRuntime.hasTap }
    var isEnabled: Bool { TapRuntime.isEnabled }

    func start() {
        guard !TapRuntime.hasTap,
              AccessibilityPermission.isTrusted,
              !SettingsStore.shared.settings.isNoOp
        else { return }

        publishSettings()

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                           place: .headInsertEventTap,
                                           options: .defaultTap,
                                           eventsOfInterest: mask,
                                           callback: scrollTapCallback,
                                           userInfo: nil)
        else { return }

        TapRuntime.setTap(port)
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func stop() {
        TapRuntime.disableAndClear()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
    }

    /// Start or stop to match current settings. There is no reason to sit in
    /// the event stream when every device is set to pass through untouched.
    func syncWithSettings() {
        publishSettings()
        SettingsStore.shared.settings.isNoOp ? stop() : start()
    }

    /// Snapshot of what the tap has actually handled.
    var eventCounts: (seen: Int, flipped: Int, lastContinuous: Bool) {
        let c = TapRuntime.counts.withLock { $0 }
        return (c.seen, c.flipped, c.lastWasContinuous)
    }

    /// Before/after deltas of the most recent event, to confirm the flip is
    /// coherent across all three encodings rather than only one.
    var lastDeltas: (lineIn: Int, pointIn: Int, lineOut: Int, pointOut: Int) {
        let c = TapRuntime.counts.withLock { $0 }
        return (c.lastLineIn, c.lastPointIn, c.lastLineOut, c.lastPointOut)
    }

    var recentEvents: [String] { TapRuntime.counts.withLock { $0.recent } }

    /// Which device the most recent scroll came from, as Scroll judged it.
    var lastSource: ScrollSource? {
        TapRuntime.counts.withLock { $0.lastWasTrackpad }.map { $0 ? .trackpad : .mouse }
    }
    var transitions: [String] { TapRuntime.counts.withLock { $0.transitions } }

    var perDevice: (trackpad: Int, mouse: Int) {
        let c = TapRuntime.counts.withLock { $0 }
        return (c.trackpadEvents, c.mouseEvents)
    }

    var health: (timeouts: Int, userInput: Int, phase: Int, momentum: Int) {
        let c = TapRuntime.counts.withLock { $0 }
        return (c.disabledByTimeout, c.disabledByUserInput, c.lastScrollPhase, c.lastMomentumPhase)
    }

    private func publishSettings() {
        // Read on the actor first: `withLock`'s closure is Sendable and cannot
        // reach main-actor state from inside.
        let current = SettingsStore.shared.settings
        TapRuntime.settings.withLock { $0 = current }
    }
}

// MARK: - What the callback is allowed to touch

private enum TapRuntime {

    /// Read on the event-tap thread, written on the main actor. A lock rather
    /// than an unguarded global because "it's only three booleans" is exactly
    /// the reasoning that produces real races.
    static let settings = OSAllocatedUnfairLock(initialState: ScrollSettings.standard)

    /// Counters, so "is it actually doing anything" is answerable rather than
    /// inferred. Every failure mode here is otherwise invisible.
    struct Counts: Sendable {
        var seen = 0
        var flipped = 0
        var lastWasContinuous = false
        /// Nil until the first event, so "last scroll came from" can say so.
        var lastWasTrackpad: Bool?
        var lastLineIn = 0
        var lastPointIn = 0
        var lastLineOut = 0
        var lastPointOut = 0
        /// The system disables a tap it considers too slow. Each disable is a
        /// visible gap where scrolling stops responding entirely.
        var disabledByTimeout = 0
        var disabledByUserInput = 0
        /// Phase fields, which is where device switches show up.
        var lastScrollPhase = 0
        var lastMomentumPhase = 0
        /// A short history, so the moment of switching devices is visible
        /// rather than inferred. Momentum from a trackpad flick continuing
        /// after the mouse is touched is the leading theory for the stall.
        var recent: [String] = []
        /// Only device switches, with the gap before them. A long gap here is
        /// the stall, and tells us whether it is something Scroll causes
        /// or simply how long the hardware takes to hand over.
        var transitions: [String] = []
        var lastEventAt: Date?
        var lastKindContinuous: Bool?
        /// Per-device totals, which a short ring buffer cannot flush away.
        var trackpadEvents = 0
        var mouseEvents = 0
    }
    static let counts = OSAllocatedUnfairLock(initialState: Counts())

    /// Read once at startup, not per event.
    static let verbose =
        UserDefaults.standard.bool(forKey: "vellscroll.verbose")

    /// `CFMachPort` is not `Sendable`. It is created and destroyed only on the
    /// main actor during start/stop, and read from the callback solely to
    /// re-enable a tap the system just disabled — a single pointer read of a
    /// value that is non-nil for the whole time the callback can run.
    nonisolated(unsafe) private static var tap: CFMachPort?

    static var hasTap: Bool { tap != nil }

    /// A tap can exist yet be disabled — the system switches one off if it is
    /// too slow, and it starts disabled if creation half-succeeded.
    static var isEnabled: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    static func setTap(_ port: CFMachPort) { tap = port }

    static func disableAndClear() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
    }

    /// The system disables a tap that takes too long, or on certain user input.
    /// Re-enabling is not optional: without it Scroll silently stops
    /// working, and the only symptom is scrolling quietly going back to normal.
    static func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    static func transform(_ event: CGEvent) {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        // The phases decide trackpad versus mouse: a smooth mouse wheel is
        // continuous too, but only a gesture surface reports a phase.
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let source = ScrollSource.classify(isContinuous: isContinuous,
                                           scrollPhase: phase, momentumPhase: momentum)
        let isTrackpad = source == .trackpad
        let current = settings.withLock { $0 }
        let decision = ScrollPolicy.decide(isContinuous: isContinuous,
                                           scrollPhase: phase, momentumPhase: momentum,
                                           settings: current)

        counts.withLock {
            $0.seen += 1
            $0.lastWasContinuous = isContinuous
            $0.lastWasTrackpad = isTrackpad
            $0.lastScrollPhase = Int(phase)
            $0.lastMomentumPhase = Int(momentum)
            if !decision.isIdentity { $0.flipped += 1 }

            if isTrackpad { $0.trackpadEvents += 1 } else { $0.mouseEvents += 1 }

            // Verbose history is opt-in. Building strings and reading the clock
            // on every scroll event is fine while debugging and pure waste in a
            // shipped build — this is the hottest path in the app.
            //   defaults write com.vellund.Vellforge vellscroll.verbose -bool true
            if TapRuntime.verbose {
                let kind = isTrackpad ? "trackpad" : (isContinuous ? "smooth wheel" : "mouse   ")
                let flip = decision.isIdentity ? "pass" : "FLIP"
                $0.recent.append("\(kind) phase=\(phase) momentum=\(momentum) \(flip)")
                if $0.recent.count > 12 { $0.recent.removeFirst() }

                let now = Date()
                let gapMs = $0.lastEventAt.map { Int(now.timeIntervalSince($0) * 1000) } ?? -1
                if let previous = $0.lastKindContinuous, previous != isTrackpad {
                    let from = previous ? "trackpad" : "mouse"
                    let to = isTrackpad ? "trackpad" : "mouse"
                    $0.transitions.append("\(from) -> \(to)   gap \(gapMs)ms")
                    if $0.transitions.count > 10 { $0.transitions.removeFirst() }
                }
                $0.lastEventAt = now
                $0.lastKindContinuous = isTrackpad
            }
        }

        guard !decision.isIdentity else { return }

        let beforeLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let beforePoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)

        if decision.invertVertical { negate(event, axis: 1) }
        if decision.invertHorizontal { negate(event, axis: 2) }

        let afterLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let afterPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        counts.withLock {
            $0.lastLineIn = Int(beforeLine);  $0.lastPointIn = Int(beforePoint)
            $0.lastLineOut = Int(afterLine);  $0.lastPointOut = Int(afterPoint)
        }
    }

    /// A scroll event carries the same movement in three parallel encodings —
    /// line, pixel, and fixed-point. Flipping only one leaves apps disagreeing
    /// about which way the user scrolled, so all three move together.
    private static func negate(_ event: CGEvent, axis: Int) {
        let line: CGEventField  = axis == 1 ? .scrollWheelEventDeltaAxis1
                                            : .scrollWheelEventDeltaAxis2
        let point: CGEventField = axis == 1 ? .scrollWheelEventPointDeltaAxis1
                                            : .scrollWheelEventPointDeltaAxis2
        let fixed: CGEventField = axis == 1 ? .scrollWheelEventFixedPtDeltaAxis1
                                            : .scrollWheelEventFixedPtDeltaAxis2

        // Read all three BEFORE writing any of them. Setting one delta makes
        // CoreGraphics recompute the others, so interleaving reads and writes
        // negates the already-negated values — the line delta ends up flipped
        // while point and fixed are flipped back. Most apps read the point
        // delta, so the visible result is nothing happening at all.
        let lineValue = event.getIntegerValueField(line)
        let pointValue = event.getIntegerValueField(point)
        let fixedValue = event.getDoubleValueField(fixed)

        event.setIntegerValueField(line, value: -lineValue)
        event.setIntegerValueField(point, value: -pointValue)
        event.setDoubleValueField(fixed, value: -fixedValue)
    }
}

private let scrollTapCallback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .tapDisabledByTimeout:
        TapRuntime.counts.withLock { $0.disabledByTimeout += 1 }
        TapRuntime.reenable()
        return nil
    case .tapDisabledByUserInput:
        TapRuntime.counts.withLock { $0.disabledByUserInput += 1 }
        TapRuntime.reenable()
        return nil
    case .scrollWheel:
        TapRuntime.transform(event)
        return Unmanaged.passUnretained(event)
    default:
        return Unmanaged.passUnretained(event)
    }
}
