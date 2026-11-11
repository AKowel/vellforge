import CoreGraphics

/// A screen, reduced to what the geometry layer actually needs.
///
/// Deliberately free of `NSScreen` so zone resolution can be tested against
/// synthetic multi-monitor arrangements — including the mismatched-height and
/// stacked layouts that break naive coordinate maths.
public struct Display: Equatable, Sendable, Identifiable {
    /// Stable across reconnects, unlike a screen index. Derived from
    /// `CGDisplayCreateUUIDFromDisplayID` at the app layer.
    public let id: String

    /// Full bounds in AppKit coordinates.
    public let frame: CGRect

    /// Usable bounds, excluding the menu bar and Dock. AppKit coordinates.
    public let visibleFrame: CGRect

    public init(id: String, frame: CGRect, visibleFrame: CGRect) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    public func contains(point: CGPoint) -> Bool {
        frame.contains(point)
    }
}

public extension Array where Element == Display {
    /// The display containing `point`, falling back to the one whose centre is
    /// nearest. A window dragged past the edge of every screen still has to land
    /// somewhere sensible.
    func containing(_ point: CGPoint) -> Display? {
        if let hit = first(where: { $0.contains(point: point) }) { return hit }
        return self.min { a, b in
            a.frame.center.distanceSquared(to: point) < b.frame.center.distanceSquared(to: point)
        }
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

extension CGPoint {
    func distanceSquared(to other: CGPoint) -> CGFloat {
        let dx = x - other.x, dy = y - other.y
        return dx * dx + dy * dy
    }
}
