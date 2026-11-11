import CoreGraphics
import Foundation

/// One icon in the menu bar, as seen from outside the app that owns it.
///
/// Identified by **window ID**, not by owner. Modern macOS renders every status
/// item — third-party included — inside the ControlCenter process, so the
/// window list reports ControlCenter as the owner of all of them. The window ID
/// is the only thing that distinguishes one item from another, and it is also
/// what lets each icon be captured individually.
public struct MenuBarItem: Sendable, Equatable, Identifiable {
    public let windowID: UInt32
    public let frame: CGRect
    /// A name, when Accessibility can supply one. Usually it cannot.
    public let name: String?

    public var id: UInt32 { windowID }

    public init(windowID: UInt32, frame: CGRect, name: String? = nil) {
        self.windowID = windowID
        self.frame = frame
        self.name = name
    }

    /// Where a synthesised click should land to activate this item.
    public var clickPoint: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Status items are roughly square. Anything much wider is a text readout —
    /// a clock, a battery percentage, a stock ticker — rather than an icon.
    public var looksLikeText: Bool {
        frame.height > 0 && frame.width / frame.height > 2.2
    }

    public func withName(_ name: String?) -> MenuBarItem {
        MenuBarItem(windowID: windowID, frame: frame, name: name)
    }
}

public enum MenuBarLayout {

    /// Menu bar items read right to left: the rightmost sits nearest the clock.
    /// Sorting descending by x gives the order a person sees.
    public static func inVisualOrder(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.sorted { $0.frame.minX > $1.frame.minX }
    }

    /// Drops items that are ours, and any that are implausibly small — macOS
    /// keeps zero-width placeholder windows at the status level.
    public static func plausible(_ items: [MenuBarItem],
                                 excluding ownIDs: Set<UInt32> = []) -> [MenuBarItem] {
        inVisualOrder(items.filter {
            !ownIDs.contains($0.windowID) && $0.frame.width >= 8 && $0.frame.height >= 8
        })
    }

    /// Items to the left of the separator — the ones pushed off-screen when
    /// Vellbar collapses.
    public static func hidden(_ items: [MenuBarItem],
                              leftOfSeparatorX x: CGFloat) -> [MenuBarItem] {
        inVisualOrder(items.filter { $0.frame.maxX <= x })
    }

    /// Items that stay on show.
    public static func alwaysVisible(_ items: [MenuBarItem],
                                     leftOfSeparatorX x: CGFloat) -> [MenuBarItem] {
        inVisualOrder(items.filter { $0.frame.maxX > x })
    }
}
