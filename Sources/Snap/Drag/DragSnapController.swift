import AppKit
import VellforgeKit
import ApplicationServices
import SnapCore

/// Drag a window to a screen edge — or into the layout chooser at the top of
/// the screen — see where it will land, release to snap.
@MainActor
final class DragSnapController {

    static let shared = DragSnapController()

    private let monitor = DragMonitor()
    private let preview = PreviewOverlay()
    private let layoutBar = LayoutBarOverlay()
    private let map = HotZoneMap()

    private var state: DragState?

    private struct DragState {
        let window: AXUIElement
        let startFrameAX: CGRect
        /// Whether we have proven this is a *window* drag, not a text selection
        /// or a file drag that happens to be passing over a screen edge.
        var isWindowDrag = false
        var lastCheck = Date.distantPast
        var targetRect: CGRect?
        let startedAt = Date()
        /// Whether we already fell back to the focused window once.
        var triedFocused = false
    }

    /// How far the window must actually move before we believe it is being
    /// dragged. Below this, a click that jitters would arm the preview. Small,
    /// so the preview and layout bar appear the moment a window moves.
    private let movementThreshold: CGFloat = 4
    /// Accessibility reads are IPC, and drag events fire ~120×/second. Only poll
    /// while still deciding whether this is a window drag; once confirmed the
    /// rest is pure cursor arithmetic and costs nothing.
    private let confirmInterval: TimeInterval = 0.03

    /// Set by the add-on while Snap is running. Flipping the preference in
    /// Settings must not start a drag monitor while Snap itself is switched off.
    var isActive = false

    // Keys are the ones Vellsnap used, so importing its settings is a copy.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "vellsnap.dragSnap") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "vellsnap.dragSnap")
            newValue ? shared.start() : shared.stop()
        }
    }

    static var layoutBarEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "vellsnap.layoutBar") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "vellsnap.layoutBar") }
    }

    private init() {
        monitor.onDrag = { [weak self] point in self?.handleDrag(at: point) }
        monitor.onDrop = { [weak self] point in self?.handleDrop(at: point) }
    }

    func start() {
        guard isActive, Self.isEnabled, AccessibilityPermission.isTrusted else { return }
        monitor.start()
    }

    func stop() {
        monitor.stop()
        reset()
    }

    // MARK: Drag

    private func handleDrag(at point: CGPoint) {
        if state == nil { beginDrag() }
        guard var current = state else { return }

        if !current.isWindowDrag {
            guard confirmWindowDrag(&current) else {
                state = current
                return
            }
        }

        // From here it is pure geometry — no more Accessibility traffic.
        guard let display = ScreenBridge.displays().containing(point) else {
            state = current
            return
        }

        // The layout chooser takes priority over edge targets wherever both
        // could apply, because the user had to travel into it deliberately.
        if Self.layoutBarEnabled,
           layoutBar.geometry.shouldReveal(at: point, in: display) {
            layoutBar.show(in: display)

            if let hit = layoutBar.geometry.hitTest(point,
                                                    layouts: layoutBar.layouts,
                                                    in: display) {
                layoutBar.highlight(hit)
                let zone = layoutBar.layouts[hit.layoutIndex].cells[hit.cellIndex]
                let rect = zone.resolve(in: display.visibleFrame,
                                        gap: Double(SnapEngine.gap))
                current.targetRect = rect
                preview.show(rect)
                state = current
                return
            }
            layoutBar.highlight(nil)
        } else {
            layoutBar.hide()
        }

        // Fall back to edge targets — including the very top edge, which sits
        // above the bar and still maximises.
        if let target = map.target(at: point, in: display) {
            let zone = target.zone(cycle: Self.cycleStep(for: NSEvent.modifierFlags))
            let rect = zone.resolve(in: display.visibleFrame, gap: Double(SnapEngine.gap))
            current.targetRect = rect
            preview.show(rect)
        } else {
            current.targetRect = nil
            preview.hide()
        }
        state = current
    }

    /// Returns true once the window has actually moved far enough to count.
    private func confirmWindowDrag(_ current: inout DragState) -> Bool {
        let now = Date()
        guard now.timeIntervalSince(current.lastCheck) >= confirmInterval else { return false }
        current.lastCheck = now

        guard let live = WindowController.frame(of: current.window) else { return false }
        let moved = hypot(live.minX - current.startFrameAX.minX,
                          live.minY - current.startFrameAX.minY)
        guard moved >= movementThreshold else {
            // Still not moving after a moment: we may have picked the wrong
            // window. Try the focused one, once.
            if !current.triedFocused, now.timeIntervalSince(current.startedAt) > 0.25,
               let focused = WindowController.focusedWindow(),
               let frame = WindowController.frame(of: focused) {
                current = DragState(window: focused, startFrameAX: frame, triedFocused: true)
            }
            return false
        }

        current.isWindowDrag = true
        return true
    }

    private func beginDrag() {
        // The window under the pointer is the one being dragged.
        let mouse = NSEvent.mouseLocation
        let pointAX = CGPoint(x: mouse.x, y: ScreenBridge.primaryMaxY - mouse.y)
        guard let window = WindowController.window(at: pointAX) ?? WindowController.focusedWindow(),
              !WindowController.isFullScreen(window),
              let frame = WindowController.frame(of: window)
        else { return }
        state = DragState(window: window, startFrameAX: frame)
    }

    /// Holding a modifier steps through what an edge offers, so one drop region
    /// serves half → third → two-thirds without extra targets to aim at.
    private static func cycleStep(for flags: NSEvent.ModifierFlags) -> Int {
        if flags.contains(.control) && flags.contains(.shift) { return 2 }
        if flags.contains(.control) { return 1 }
        return 0
    }

    // MARK: Drop

    private func handleDrop(at point: CGPoint) {
        defer { reset() }
        guard let state, state.isWindowDrag, let rect = state.targetRect else { return }
        preview.dismissImmediately()
        layoutBar.dismissImmediately()

        if !SnapEngine.apply(rect, to: state.window) {
            Feedback.show(SnapError.windowRefusedMove.localizedDescription)
        }
    }

    private func reset() {
        state = nil
        preview.hide()
        layoutBar.hide()
    }
}
