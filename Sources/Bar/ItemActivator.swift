import AppKit
import CoreGraphics

/// Clicks a menu bar item on the user's behalf.
///
/// There is no way to ask another app's status item to activate itself, so
/// Bar synthesises a click at its coordinates. That only works while the
/// item is actually on screen, which is why activation reveals first.
@MainActor
enum ItemActivator {

    static func click(at point: CGPoint) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source,
                    mouseType: type,
                    mouseCursorPosition: point,
                    mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }
}
