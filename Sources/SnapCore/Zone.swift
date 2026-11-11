import CoreGraphics

/// A rectangular region of a screen, expressed as fractions of that screen.
///
/// Coordinates are **top-left origin**: `y == 0` is the top edge, `y == 1` the
/// bottom. This matches how people describe layouts ("top-left quarter") and how
/// the Accessibility API addresses the screen. AppKit's bottom-left origin is
/// dealt with exactly once, in `resolve(in:gap:)`.
public struct Zone: Equatable, Sendable, Codable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Resolve this zone against a screen's visible frame, in **AppKit
    /// coordinates** (bottom-left origin).
    ///
    /// - Parameters:
    ///   - visibleFrame: the screen's usable area, excluding menu bar and Dock.
    ///   - gap: inset applied on every edge of the resulting rect, in points.
    public func resolve(in visibleFrame: CGRect, gap: Double = 0) -> CGRect {
        let w = visibleFrame.width * width
        let h = visibleFrame.height * height
        let originX = visibleFrame.minX + visibleFrame.width * x

        // `y` measures down from the top; AppKit measures up from the bottom.
        let distanceFromTop = visibleFrame.height * y
        let originY = visibleFrame.maxY - distanceFromTop - h

        let rect = CGRect(x: originX, y: originY, width: w, height: h)
        guard gap > 0 else { return rect }

        // Never let the gap invert the rect.
        let inset = min(gap, rect.width / 2 - 1, rect.height / 2 - 1)
        guard inset > 0 else { return rect }
        return rect.insetBy(dx: inset, dy: inset)
    }
}

// MARK: - Presets

public extension Zone {
    static let full        = Zone(x: 0,     y: 0,   width: 1,     height: 1)

    static let leftHalf    = Zone(x: 0,     y: 0,   width: 1 / 2, height: 1)
    static let rightHalf   = Zone(x: 1 / 2, y: 0,   width: 1 / 2, height: 1)
    static let topHalf     = Zone(x: 0,     y: 0,   width: 1,     height: 1 / 2)
    static let bottomHalf  = Zone(x: 0,     y: 1 / 2, width: 1,   height: 1 / 2)

    static let topLeft     = Zone(x: 0,     y: 0,     width: 1 / 2, height: 1 / 2)
    static let topRight    = Zone(x: 1 / 2, y: 0,     width: 1 / 2, height: 1 / 2)
    static let bottomLeft  = Zone(x: 0,     y: 1 / 2, width: 1 / 2, height: 1 / 2)
    static let bottomRight = Zone(x: 1 / 2, y: 1 / 2, width: 1 / 2, height: 1 / 2)

    static let leftThird   = Zone(x: 0,     y: 0, width: 1 / 3, height: 1)
    static let centerThird = Zone(x: 1 / 3, y: 0, width: 1 / 3, height: 1)
    static let rightThird  = Zone(x: 2 / 3, y: 0, width: 1 / 3, height: 1)

    static let leftTwoThirds  = Zone(x: 0,     y: 0, width: 2 / 3, height: 1)
    static let rightTwoThirds = Zone(x: 1 / 3, y: 0, width: 2 / 3, height: 1)
}

/// The named actions Vellsnap can perform. Kept separate from `Zone` because
/// some actions (centring, moving between displays) are not a zone at all.
public enum SnapAction: String, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird
    case leftTwoThirds, rightTwoThirds
    case maximize
    case center

    /// The zone this action resolves to, or `nil` for actions that are not a
    /// simple region (currently only `.center`, which preserves window size).
    public var zone: Zone? {
        switch self {
        case .leftHalf:       return .leftHalf
        case .rightHalf:      return .rightHalf
        case .topHalf:        return .topHalf
        case .bottomHalf:     return .bottomHalf
        case .topLeft:        return .topLeft
        case .topRight:       return .topRight
        case .bottomLeft:     return .bottomLeft
        case .bottomRight:    return .bottomRight
        case .leftThird:      return .leftThird
        case .centerThird:    return .centerThird
        case .rightThird:     return .rightThird
        case .leftTwoThirds:  return .leftTwoThirds
        case .rightTwoThirds: return .rightTwoThirds
        case .maximize:       return .full
        case .center:         return nil
        }
    }

    public var title: String {
        switch self {
        case .leftHalf:       return "Left Half"
        case .rightHalf:      return "Right Half"
        case .topHalf:        return "Top Half"
        case .bottomHalf:     return "Bottom Half"
        case .topLeft:        return "Top Left"
        case .topRight:       return "Top Right"
        case .bottomLeft:     return "Bottom Left"
        case .bottomRight:    return "Bottom Right"
        case .leftThird:      return "Left Third"
        case .centerThird:    return "Centre Third"
        case .rightThird:     return "Right Third"
        case .leftTwoThirds:  return "Left Two Thirds"
        case .rightTwoThirds: return "Right Two Thirds"
        case .maximize:       return "Maximise"
        case .center:         return "Centre"
        }
    }
}

/// Actions that move a window between displays rather than within one.
public enum DisplayAction: String, CaseIterable, Sendable {
    case nextDisplay, previousDisplay

    public var title: String {
        switch self {
        case .nextDisplay:     return "Move to Next Display"
        case .previousDisplay: return "Move to Previous Display"
        }
    }
}

public extension Zone {
    /// Derive a zone from a concrete rect — the inverse of `resolve(in:gap:)`.
    ///
    /// Used when capturing a layout: storing fractions rather than pixels is
    /// what lets an arrangement saved on a large monitor restore sensibly onto
    /// a smaller screen.
    init(rect: CGRect, in visibleFrame: CGRect) {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            self.init(x: 0, y: 0, width: 1, height: 1)
            return
        }
        self.init(x: Double((rect.minX - visibleFrame.minX) / visibleFrame.width),
                  y: Double((visibleFrame.maxY - rect.maxY) / visibleFrame.height),
                  width: Double(rect.width / visibleFrame.width),
                  height: Double(rect.height / visibleFrame.height))
    }
}
