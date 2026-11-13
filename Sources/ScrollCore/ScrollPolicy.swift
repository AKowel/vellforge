import Foundation

/// Where a scroll event came from.
///
/// macOS does not label events "trackpad" or "mouse". Two things it does say:
/// whether the scroll is *continuous* (smooth, small deltas) or *discrete*
/// (the notches of a wheel), and, for a gesture surface, the *phase* of the
/// gesture: began, changed, ended, then momentum after the fingers lift.
///
/// Continuity alone is not enough. A mouse with a smooth or free-spinning
/// wheel, such as Logitech's MX range, sends continuous deltas too, and was
/// taken for a trackpad. What it never sends is a gesture phase, so that is
/// the test.
public enum ScrollSource: String, Sendable, Equatable, CaseIterable {
    /// A gesture surface: trackpads, and Magic Mouse, which scrolls by gesture.
    case trackpad
    /// A wheel, notched or smooth.
    case mouse

    public var title: String {
        switch self {
        case .trackpad: return "Trackpad"
        case .mouse:    return "Mouse wheel"
        }
    }

    /// - Parameters:
    ///   - scrollPhase: the event's `scrollWheelEventScrollPhase`; 0 when the
    ///     device has no notion of a gesture.
    ///   - momentumPhase: `scrollWheelEventMomentumPhase`; non-zero while a
    ///     trackpad flick coasts on after the fingers have lifted.
    public static func classify(isContinuous: Bool,
                                scrollPhase: Int64 = 0,
                                momentumPhase: Int64 = 0) -> ScrollSource {
        guard isContinuous else { return .mouse }
        return (scrollPhase != 0 || momentumPhase != 0) ? .trackpad : .mouse
    }
}

/// What the user has asked for.
///
/// The entire reason this app exists: macOS has exactly one "Natural scrolling"
/// checkbox, and it applies to every pointing device at once. Anyone who wants
/// natural scrolling on a trackpad and traditional scrolling on an external
/// mouse cannot express that in System Settings.
public struct ScrollSettings: Codable, Sendable, Equatable {
    public var invertMouse: Bool
    public var invertTrackpad: Bool
    /// Whether inversion also applies to left/right scrolling.
    public var invertHorizontal: Bool

    public init(invertMouse: Bool = true,
                invertTrackpad: Bool = false,
                invertHorizontal: Bool = false) {
        self.invertMouse = invertMouse
        self.invertTrackpad = invertTrackpad
        self.invertHorizontal = invertHorizontal
    }

    /// The default that matches why people install this: leave the trackpad
    /// alone, flip the mouse.
    public static let standard = ScrollSettings()

    /// Nothing to do — lets the tap skip work entirely.
    public var isNoOp: Bool { !invertMouse && !invertTrackpad }
}

public enum ScrollPolicy {

    public static func shouldInvertVertical(source: ScrollSource,
                                            settings: ScrollSettings) -> Bool {
        switch source {
        case .mouse:    return settings.invertMouse
        case .trackpad: return settings.invertTrackpad
        }
    }

    public static func shouldInvertHorizontal(source: ScrollSource,
                                              settings: ScrollSettings) -> Bool {
        settings.invertHorizontal && shouldInvertVertical(source: source, settings: settings)
    }

    /// Convenience for the tap: what to do with one event, in one call.
    public struct Decision: Equatable, Sendable {
        public let invertVertical: Bool
        public let invertHorizontal: Bool

        public var isIdentity: Bool { !invertVertical && !invertHorizontal }
    }

    public static func decide(isContinuous: Bool,
                              scrollPhase: Int64 = 0,
                              momentumPhase: Int64 = 0,
                              settings: ScrollSettings) -> Decision {
        let source = ScrollSource.classify(isContinuous: isContinuous,
                                           scrollPhase: scrollPhase,
                                           momentumPhase: momentumPhase)
        return Decision(
            invertVertical: shouldInvertVertical(source: source, settings: settings),
            invertHorizontal: shouldInvertHorizontal(source: source, settings: settings))
    }
}

/// Which way content actually moves, once the system setting and Vellscroll's
/// inversion are both taken into account.
public enum ScrollDirection: String, Sendable, Equatable {
    /// Content follows your fingers, the way a phone works.
    case natural
    /// The wheel moves the view, the way it always did.
    case traditional

    public var title: String {
        switch self {
        case .natural:     return "natural"
        case .traditional: return "traditional"
        }
    }
}

/// Resolves what a device really does.
///
/// This matters because Vellscroll only ever *flips* — it has no absolute
/// setting of its own. The same configuration produces opposite results
/// depending on the system's own "natural scrolling" switch, so the app has to
/// read that to describe itself honestly.
public enum EffectiveDirection {

    public static func resolve(source: ScrollSource,
                               systemNatural: Bool,
                               settings: ScrollSettings) -> ScrollDirection {
        let base: ScrollDirection = systemNatural ? .natural : .traditional
        let inverted = ScrollPolicy.shouldInvertVertical(source: source, settings: settings)
        guard inverted else { return base }
        return base == .natural ? .traditional : .natural
    }

    /// The arrangement most people are after: a trackpad that behaves like a
    /// phone, and a mouse wheel that behaves like a mouse wheel.
    public static func isConventional(systemNatural: Bool,
                                      settings: ScrollSettings) -> Bool {
        resolve(source: .trackpad, systemNatural: systemNatural, settings: settings) == .natural
            && resolve(source: .mouse, systemNatural: systemNatural, settings: settings) == .traditional
    }

    /// Settings that produce the conventional arrangement for a given system
    /// switch — so the app can offer to fix itself in one click.
    public static func conventionalSettings(systemNatural: Bool,
                                            keepingHorizontal horizontal: Bool = false) -> ScrollSettings {
        // Invert whichever device the system setting is currently wrong for.
        ScrollSettings(invertMouse: systemNatural,
                       invertTrackpad: !systemNatural,
                       invertHorizontal: horizontal)
    }
}
