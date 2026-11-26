import CoreGraphics

/// A drop target along a screen edge.
public enum EdgeTarget: String, Sendable, Equatable, CaseIterable {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight

    /// Zones this target offers, in cycling order. Holding a modifier while
    /// dragging steps through them, so one edge serves three layouts without
    /// needing three separate drop regions.
    public var cycle: [Zone] {
        switch self {
        case .left:        return [.leftHalf, .leftThird, .leftTwoThirds]
        case .right:       return [.rightHalf, .rightThird, .rightTwoThirds]
        case .top:         return [.full, .topHalf]
        case .bottom:      return [.bottomHalf, .centerThird]
        case .topLeft:     return [.topLeft]
        case .topRight:    return [.topRight]
        case .bottomLeft:  return [.bottomLeft]
        case .bottomRight: return [.bottomRight]
        }
    }

    public func zone(cycle step: Int = 0) -> Zone {
        let options = cycle
        guard step > 0 else { return options[0] }
        return options[step % options.count]
    }
}

/// Maps a cursor position to a drop target.
///
/// Distances are measured against the display's **full frame**, not its visible
/// frame: the cursor can reach the physical screen edge, and requiring it to
/// stop short of the menu bar would make the top target nearly unhittable.
public struct HotZoneMap: Sendable {

    /// How close to an edge the cursor must be to arm a target.
    public var edgeDepth: CGFloat
    /// How far along an edge still counts as its corner.
    public var cornerSize: CGFloat

    public init(edgeDepth: CGFloat = 12, cornerSize: CGFloat = 80) {
        self.edgeDepth = edgeDepth
        self.cornerSize = cornerSize
    }

    /// - Parameter others: every other display. An edge where another display
    ///   carries on is a seam the pointer passes straight through, not an edge
    ///   it can push against, so it arms nothing. Without this, moving a window
    ///   to the screen beside it snaps it to that screen's near half.
    public func target(at point: CGPoint, in display: Display,
                       others: [Display] = []) -> EdgeTarget? {
        let f = display.frame
        let neighbours = others.filter { $0.id != display.id }
        func continues(_ probe: CGPoint) -> Bool {
            neighbours.contains { $0.contains(point: probe) }
        }

        // AppKit: y grows upward, so "top" is the high-y edge. Probes sit half
        // a point past each edge, where a neighbour's half-open frame starts.
        let nearLeft   = point.x <= f.minX + edgeDepth
            && !continues(CGPoint(x: f.minX - 0.5, y: point.y))
        let nearRight  = point.x >= f.maxX - edgeDepth
            && !continues(CGPoint(x: f.maxX + 0.5, y: point.y))
        let nearTop    = point.y >= f.maxY - edgeDepth
            && !continues(CGPoint(x: point.x, y: f.maxY + 0.5))
        let nearBottom = point.y <= f.minY + edgeDepth
            && !continues(CGPoint(x: point.x, y: f.minY - 0.5))

        guard nearLeft || nearRight || nearTop || nearBottom else { return nil }
        // Ignore points outside the display entirely.
        guard point.x >= f.minX - edgeDepth, point.x <= f.maxX + edgeDepth,
              point.y >= f.minY - edgeDepth, point.y <= f.maxY + edgeDepth
        else { return nil }

        let inTopBand    = point.y >= f.maxY - cornerSize
        let inBottomBand = point.y <= f.minY + cornerSize
        let inLeftBand   = point.x <= f.minX + cornerSize
        let inRightBand  = point.x >= f.maxX - cornerSize

        // Corners win wherever the regions overlap — a drag into the very
        // corner should give a quarter, never a half.
        if (nearLeft && inTopBand)    || (nearTop && inLeftBand)     { return .topLeft }
        if (nearRight && inTopBand)   || (nearTop && inRightBand)    { return .topRight }
        if (nearLeft && inBottomBand) || (nearBottom && inLeftBand)  { return .bottomLeft }
        if (nearRight && inBottomBand) || (nearBottom && inRightBand) { return .bottomRight }

        if nearTop    { return .top }
        if nearLeft   { return .left }
        if nearRight  { return .right }
        if nearBottom { return .bottom }
        return nil
    }
}
