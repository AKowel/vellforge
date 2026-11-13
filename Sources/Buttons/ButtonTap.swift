import AppKit
import ButtonsCore
import Carbon.HIToolbox
import CoreGraphics
import VellforgeKit

/// Watches clicks, side buttons and fingers on the trackpad, and rewrites the
/// ones Buttons is asked to.
///
/// One `CGEvent` tap, because events have to be *changed* (a left click
/// becomes a middle click) or *swallowed* (a side button press becomes ⌘[),
/// which needs Accessibility. Gesture events are listened to only for the
/// finger count; nothing about them is changed or kept.
///
/// The tap's run loop source is on the main run loop, so its callback runs on
/// the main thread, which is what makes `assumeIsolated` sound below.
@MainActor
final class ButtonTap {

    static let shared = ButtonTap()
    private init() {}

    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    private(set) var settings = ButtonSettings.standard
    /// Three-finger drag turns a three-finger press into a drag. Converting
    /// that press to a middle click would break it, so click conversion stands
    /// down while it's on.
    private(set) var threeFingerDragIsOn = false

    // Live state.
    private var fingers = 0
    private var recogniser = TapRecogniser()
    private var convertingClick = false

    // Counters for diagnostics.
    private(set) var sideButtonPresses = 0
    private(set) var middleClicks = 0
    private(set) var middleTaps = 0
    private(set) var gestureEventsSeen = 0
    private(set) var timeouts = 0

    var isRunning: Bool { port != nil }
    var isEnabled: Bool { port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    var fingersNow: Int { fingers }

    func apply(_ settings: ButtonSettings) {
        self.settings = settings
        threeFingerDragIsOn = TrackpadSettings.threeFingerDrag
        if settings.isNoOp { stop() } else { start() }
    }

    func start() {
        guard port == nil, AccessibilityPermission.isTrusted, !settings.isNoOp else { return }

        var mask: CGEventMask = 0
        for type: CGEventType in [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                  .otherMouseDown, .otherMouseUp] {
            mask |= CGEventMask(1) << CGEventMask(type.rawValue)
        }
        // NSEvent.EventType.gesture: where the finger touches arrive.
        mask |= CGEventMask(1) << CGEventMask(NSEvent.EventType.gesture.rawValue)

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: buttonTapCallback,
                                          userInfo: nil)
        else { return }
        port = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
        fingers = 0
        recogniser.reset()
        convertingClick = false
    }

    fileprivate func reenable() {
        timeouts += 1
        if let port { CGEvent.tapEnable(tap: port, enable: true) }
    }

    /// Returns false to swallow the event.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case _ where type.rawValue == CGEventType.RawValue(NSEvent.EventType.gesture.rawValue):
            guard settings.wantsTouches else { return true }
            gestureEventsSeen += 1
            touchesChanged(event)
            return true

        case .leftMouseDown:
            // A press of the trackpad with three fingers resting on it.
            guard settings.middleClick, !threeFingerDragIsOn, fingers == 3 else { return true }
            convertingClick = true
            recogniser.spoil()
            middleClicks += 1
            makeMiddle(event, .otherMouseDown)
            return true

        case .leftMouseDragged:
            if convertingClick { makeMiddle(event, .otherMouseDragged) }
            return true

        case .leftMouseUp:
            guard convertingClick else { return true }
            convertingClick = false
            makeMiddle(event, .otherMouseUp)
            return true

        case .otherMouseDown, .otherMouseUp:
            guard settings.sideButtons else { return true }
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            guard let navigation = SideButtons.navigation(forButton: button,
                                                          swapped: settings.swapSideButtons)
            else { return true }
            // Act on the press; swallow both press and release so the app
            // never sees a button it might also act on.
            if type == .otherMouseDown {
                sideButtonPresses += 1
                Self.send(navigation)
            }
            return false

        default:
            return true
        }
    }

    private func touchesChanged(_ event: CGEvent) {
        guard let ns = NSEvent(cgEvent: event) else { return }
        let touching = ns.touches(matching: .touching, in: nil)
            .filter { $0.type == .indirect }  // the trackpad, not a touch screen
        fingers = touching.count
        let points = touching.map {
            TouchPoint(id: $0.identity.hash,
                       x: Double($0.normalizedPosition.x),
                       y: Double($0.normalizedPosition.y))
        }
        let tapped = recogniser.update(points, at: ProcessInfo.processInfo.systemUptime)
        if tapped, settings.middleTap {
            middleTaps += 1
            // Post after this callback returns rather than from inside it.
            DispatchQueue.main.async { Self.postMiddleClick() }
        }
    }

    private func makeMiddle(_ event: CGEvent, _ type: CGEventType) {
        event.type = type
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(CGMouseButton.center.rawValue))
    }

    private static func postMiddleClick() {
        let location = CGEvent(source: nil)?.location ?? .zero
        for type: CGEventType in [.otherMouseDown, .otherMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type,
                    mouseCursorPosition: location, mouseButton: .center)?
                .post(tap: .cghidEventTap)
        }
    }

    /// ⌘[ and ⌘] are back and forward in browsers, Finder, Xcode, Mail, the
    /// App Store and most other apps, which is why they're used rather than
    /// the raw buttons that only some apps understand.
    private static func send(_ navigation: Navigation) {
        let key = CGKeyCode(navigation == .back ? kVK_ANSI_LeftBracket : kVK_ANSI_RightBracket)
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }
}

private let buttonTapCallback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { ButtonTap.shared.reenable() }
        return nil
    default:
        // The tap runs on the main run loop, so the event never leaves the
        // main thread; the compiler can't see that through a C callback.
        nonisolated(unsafe) let mainThreadEvent = event
        let keep = MainActor.assumeIsolated { ButtonTap.shared.handle(type, mainThreadEvent) }
        return keep ? Unmanaged.passUnretained(event) : nil
    }
}

/// The trackpad settings that collide with three-finger middle click.
enum TrackpadSettings {

    private static func value(_ key: String) -> Int? {
        // Built-in and Magic Trackpad keep the same keys in two domains.
        for domain in ["com.apple.AppleMultitouchTrackpad",
                       "com.apple.driver.AppleBluetoothMultitouch.trackpad"] {
            CFPreferencesAppSynchronize(domain as CFString)
            if let number = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? NSNumber {
                return number.intValue
            }
        }
        return nil
    }

    /// Accessibility → Pointer Control → Trackpad Options → three-finger drag.
    static var threeFingerDrag: Bool { value("TrackpadThreeFingerDrag") == 1 }

    /// Trackpad → Look up & data detectors → Tap with three fingers.
    static var threeFingerTapLooksUp: Bool { (value("TrackpadThreeFingerTapGesture") ?? 0) != 0 }
}
