import AppKit
import VellforgeKit
import ApplicationServices
import SnapCore

enum SnapError: LocalizedError {
    case notTrusted
    case noFocusedWindow
    case windowIsFullScreen
    case windowNotResizable
    case couldNotReadFrame
    case windowRefusedMove
    case onlyOneDisplay

    var errorDescription: String? {
        switch self {
        case .notTrusted:         return "Snap needs Accessibility access."
        case .noFocusedWindow:    return "No focused window to move."
        case .windowIsFullScreen: return "Full-screen windows can't be moved. Exit full screen first."
        case .windowNotResizable: return "This window can't be resized."
        case .couldNotReadFrame:  return "Couldn't read this window's position."
        case .windowRefusedMove:  return "This app didn't accept the new size."
        case .onlyOneDisplay:     return "There's only one display."
        }
    }
}

/// Ties the pieces together: find the focused window, work out which display it
/// is on, resolve the target frame, write it back.
@MainActor
enum SnapEngine {

    /// Padding applied around every snapped window, in points.
    static var gap: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "vellsnap.gap")) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "vellsnap.gap") }
    }

    private struct Context {
        let window: AXUIElement
        let frameAppKit: CGRect
        let display: Display
        let displays: [Display]
        let primaryMaxY: CGFloat
    }

    private static func context() -> Result<Context, SnapError> {
        guard AccessibilityPermission.isTrusted else { return .failure(.notTrusted) }
        guard let window = WindowController.focusedWindow() else {
            return .failure(.noFocusedWindow)
        }
        guard !WindowController.isFullScreen(window) else {
            return .failure(.windowIsFullScreen)
        }
        guard let currentAX = WindowController.frame(of: window) else {
            return .failure(.couldNotReadFrame)
        }

        let primaryMaxY = ScreenBridge.primaryMaxY
        let frameAppKit = CoordinateSpace.toAppKit(currentAX, primaryMaxY: primaryMaxY)

        // Which screen the window is on is decided by its centre, not its
        // origin — a window straddling two displays should snap to the one it
        // mostly occupies.
        let displays = ScreenBridge.displays()
        guard let display = displays.containing(
            CGPoint(x: frameAppKit.midX, y: frameAppKit.midY))
        else { return .failure(.couldNotReadFrame) }

        return .success(Context(window: window,
                                frameAppKit: frameAppKit,
                                display: display,
                                displays: displays,
                                primaryMaxY: primaryMaxY))
    }

    @discardableResult
    static func perform(_ action: SnapAction) -> Result<CGRect, SnapError> {
        switch context() {
        case .failure(let error): return .failure(error)
        case .success(let ctx):
            let target: CGRect
            if let zone = action.zone {
                guard WindowController.isResizable(ctx.window) else {
                    return .failure(.windowNotResizable)
                }
                target = zone.resolve(in: ctx.display.visibleFrame, gap: Double(gap))
            } else {
                // .center preserves the window's own size.
                target = CoordinateSpace.centered(size: ctx.frameAppKit.size,
                                                  in: ctx.display.visibleFrame)
            }
            return write(target, ctx: ctx)
        }
    }

    /// Snap the focused window to an arbitrary zone — used by the grid picker,
    /// where the region has no name.
    @discardableResult
    static func perform(_ zone: Zone) -> Result<CGRect, SnapError> {
        switch context() {
        case .failure(let error): return .failure(error)
        case .success(let ctx):
            guard WindowController.isResizable(ctx.window) else {
                return .failure(.windowNotResizable)
            }
            let target = zone.resolve(in: ctx.display.visibleFrame, gap: Double(gap))
            return write(target, ctx: ctx)
        }
    }

    @discardableResult
    static func move(_ action: DisplayAction) -> Result<CGRect, SnapError> {
        switch context() {
        case .failure(let error): return .failure(error)
        case .success(let ctx):
            guard let destination = ctx.displays.next(after: ctx.display,
                                                      reverse: action == .previousDisplay)
            else { return .failure(.onlyOneDisplay) }

            // Proportional remap, so a right-half window stays a right-half
            // window rather than keeping its pixel size on a different screen.
            let target = ctx.display.remap(ctx.frameAppKit, to: destination)
            return write(target, ctx: ctx)
        }
    }

    private static func write(_ targetAppKit: CGRect,
                              ctx: Context) -> Result<CGRect, SnapError> {
        let targetAX = CoordinateSpace.toAccessibility(targetAppKit,
                                                       primaryMaxY: ctx.primaryMaxY)
        guard WindowController.setFrame(targetAX, of: ctx.window) else {
            return .failure(.windowRefusedMove)
        }
        return .success(targetAppKit)
    }
}

/// Single entry point for every command, whatever triggered it.
@MainActor
enum CommandRunner {
    static func run(_ command: Command) {
        let result: Result<CGRect, SnapError>
        if let snap = command.snapAction {
            result = SnapEngine.perform(snap)
        } else if let display = command.displayAction {
            result = SnapEngine.move(display)
        } else {
            return
        }
        if case .failure(let error) = result {
            Feedback.show(error.localizedDescription)
        }
    }
}

extension SnapEngine {
    /// Write an AppKit-space rect straight to a window we already hold, skipping
    /// the focused-window lookup. Used by drag snapping, which captured the
    /// window when the drag began.
    @discardableResult
    static func apply(_ rectAppKit: CGRect, to window: AXUIElement) -> Bool {
        let targetAX = CoordinateSpace.toAccessibility(rectAppKit,
                                                       primaryMaxY: ScreenBridge.primaryMaxY)
        return WindowController.setFrame(targetAX, of: window)
    }
}
