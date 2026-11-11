import CoreGraphics

/// Converts rectangles between AppKit's and the Accessibility API's coordinate
/// systems.
///
/// This is the single most common source of subtle bugs in a window manager, so
/// it lives in exactly one place and is covered by tests:
///
/// - **AppKit** (`NSScreen`, `NSWindow`): origin at the **bottom-left** of the
///   primary screen, `y` increases **upward**.
/// - **Accessibility / CoreGraphics** (`kAXPositionAttribute`): origin at the
///   **top-left** of the primary screen, `y` increases **downward**.
///
/// The flip is always relative to the **primary** display — not the display the
/// window happens to be on. Getting that wrong produces windows that land
/// plausibly but incorrectly on multi-monitor setups, which is far harder to
/// notice than an obvious failure.
public enum CoordinateSpace {

    /// Convert an AppKit rect to Accessibility coordinates.
    /// - Parameter primaryMaxY: `NSScreen.screens[0].frame.maxY`.
    public static func toAccessibility(_ rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: rect.minX,
               y: primaryMaxY - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// Convert an Accessibility rect back to AppKit coordinates.
    ///
    /// The transform is its own inverse, but both directions are named so call
    /// sites read unambiguously.
    public static func toAppKit(_ rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: rect.minX,
               y: primaryMaxY - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// Centre a window of `size` within `visibleFrame` without resizing it.
    /// Returns AppKit coordinates.
    public static func centered(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        CGRect(x: visibleFrame.midX - size.width / 2,
               y: visibleFrame.midY - size.height / 2,
               width: size.width,
               height: size.height)
    }
}
