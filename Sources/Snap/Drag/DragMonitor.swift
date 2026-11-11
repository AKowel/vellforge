import AppKit

/// Watches left-button drags system-wide.
///
/// A passive global monitor rather than a `CGEvent` tap: we only need to
/// observe, never to consume, and the drag must still reach the app that owns
/// the window. Taps are heavier, can be disabled by the system under load, and
/// would see far more than this needs.
@MainActor
final class DragMonitor {

    var onDrag: ((CGPoint) -> Void)?
    var onDrop: ((CGPoint) -> Void)?

    private var monitors: [Any] = []

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { Self.dispatch(event, to: self) }
        }) {
            monitors.append(global)
        }

        // Global monitors skip our own process, so the preview keeps updating
        // if a drag passes over one of our own windows.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { Self.dispatch(event, to: self) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    private static func dispatch(_ event: NSEvent, to monitor: DragMonitor) {
        // `NSEvent.mouseLocation` is in AppKit screen coordinates, which is the
        // same space our `Display` frames use.
        let point = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDragged: monitor.onDrag?(point)
        case .leftMouseUp:      monitor.onDrop?(point)
        default:                break
        }
    }
}
