import AppKit
import ButtonsCore
import SwiftUI
import VellforgeKit

/// Middle click from the trackpad, and mouse side buttons that go back and
/// forward everywhere.
@MainActor
public final class ButtonsAddOn: AddOn {

    public init() {}

    public let id = "buttons"
    public let name = "Buttons"
    public let tagline = "Middle click and side buttons"
    public let summary = "A three-finger click on the trackpad is a middle click, and your mouse's "
        + "side buttons go back and forward in every app."
    public let symbolName = "computermouse"

    public let permissions = [
        PermissionUse(.accessibility, required: true,
                      reason: "Turning a click into a middle click, and a side-button press into "
                            + "back or forward, means changing input events. Buttons also counts the "
                            + "fingers on the trackpad; it keeps nothing."),
    ]

    public private(set) var isRunning = false

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        ButtonsStore.shared.onChange = { ButtonTap.shared.apply($0) }
        ButtonTap.shared.apply(ButtonsStore.shared.settings)
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        ButtonsStore.shared.onChange = nil
        ButtonTap.shared.stop()
    }

    public func menuItems() -> [NSMenuItem] {
        let s = ButtonsStore.shared.settings
        return [
            ClosureMenuItem("Side buttons go back and forward", checked: s.sideButtons) {
                ButtonsStore.shared.update { $0.sideButtons.toggle() }
            },
            ClosureMenuItem("Three-finger click is a middle click", checked: s.middleClick) {
                ButtonsStore.shared.update { $0.middleClick.toggle() }
            },
            ClosureMenuItem("Three-finger tap is a middle click", checked: s.middleTap) {
                ButtonsStore.shared.update { $0.middleTap.toggle() }
            },
        ]
    }

    public func makeSettingsView() -> AnyView {
        AnyView(ButtonsSettingsView())
    }

    public func diagnostics() -> String {
        let tap = ButtonTap.shared
        let s = ButtonsStore.shared.settings
        return """
            BUTTONS
              running:                 \(isRunning)
              event tap created:       \(tap.isRunning)
              event tap enabled:       \(tap.isEnabled)
              side buttons:            \(s.sideButtons)\(s.swapSideButtons ? " (swapped)" : "")
              three-finger click:      \(s.middleClick)
              three-finger tap:        \(s.middleTap)
              macOS three-finger drag: \(TrackpadSettings.threeFingerDrag ? "ON (click conversion stands down)" : "off")
              macOS three-finger tap:  \(TrackpadSettings.threeFingerTapLooksUp ? "Look up (clashes with tap)" : "off")
              fingers on trackpad now: \(tap.fingersNow)
              gesture events seen:     \(tap.gestureEventsSeen)
              side-button presses:     \(tap.sideButtonPresses)
              middle clicks (click):   \(tap.middleClicks)
              middle clicks (tap):     \(tap.middleTaps)
              disabled by the system:  \(tap.timeouts)
            """
    }
}

@MainActor
final class ButtonsStore {

    static let shared = ButtonsStore()
    private static let key = "vellforge.buttons"

    private(set) var settings: ButtonSettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
            onChange?(settings)
        }
    }

    /// Set while the add-on runs, so a change in Settings while it is off
    /// never starts an event tap.
    var onChange: ((ButtonSettings) -> Void)?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(ButtonSettings.self, from: data) {
            settings = stored
        } else {
            settings = .standard
        }
    }

    func update(_ change: (inout ButtonSettings) -> Void) {
        var copy = settings
        change(&copy)
        settings = copy
    }
}

struct ButtonsSettingsView: View {

    @State private var settings = ButtonsStore.shared.settings
    private let dragIsOn = TrackpadSettings.threeFingerDrag
    private let tapLooksUp = TrackpadSettings.threeFingerTapLooksUp

    var body: some View {
        Section("Mouse") {
            Toggle(isOn: $settings.sideButtons) {
                Text("Side buttons go back and forward")
                Text("In every app, not only the browsers that already understand them.")
            }
            Toggle("Swap the two side buttons", isOn: $settings.swapSideButtons)
                .disabled(!settings.sideButtons)
        }

        Section {
            Toggle(isOn: $settings.middleClick) {
                Text("Three-finger click is a middle click")
                Text("Press the trackpad with three fingers resting on it: opens links in a new tab, closes tabs, pastes in Terminal.")
            }
            .disabled(dragIsOn)
            Toggle(isOn: $settings.middleTap) {
                Text("Three-finger tap is a middle click")
                Text("A quick tap without pressing. Off at first, because it's easy to do by accident.")
            }
            if dragIsOn {
                Label("Three-finger drag is on (System Settings → Accessibility → Pointer Control), and it uses the same press. Turn it off to use three-finger click.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }
            if tapLooksUp && settings.middleTap {
                Label("macOS also uses a three-finger tap for Look Up (System Settings → Trackpad). Both will happen; switch one off.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }
        } header: {
            Text("Trackpad")
        } footer: {
            Text("Three-finger swipes, such as Mission Control, carry on working: a swipe moves, a tap doesn't.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: settings) { _, new in ButtonsStore.shared.update { $0 = new } }
        .onAppear { settings = ButtonsStore.shared.settings }
    }
}
