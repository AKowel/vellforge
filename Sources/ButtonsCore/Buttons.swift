import Foundation

/// What the user has asked Buttons to do.
public struct ButtonSettings: Codable, Sendable, Equatable {
    /// Mouse side buttons go back and forward in every app.
    public var sideButtons: Bool
    /// For mice whose buttons are the other way round.
    public var swapSideButtons: Bool
    /// Clicking the trackpad with three fingers is a middle click.
    public var middleClick: Bool
    /// Tapping the trackpad with three fingers is a middle click.
    public var middleTap: Bool

    public init(sideButtons: Bool = true, swapSideButtons: Bool = false,
                middleClick: Bool = true, middleTap: Bool = false) {
        self.sideButtons = sideButtons
        self.swapSideButtons = swapSideButtons
        self.middleClick = middleClick
        self.middleTap = middleTap
    }

    /// Side buttons and three-finger click on, tap off: a tap is easy to make
    /// by accident, so it's opt-in.
    public static let standard = ButtonSettings()

    /// Nothing to do, so no event tap at all.
    public var isNoOp: Bool { !sideButtons && !middleClick && !middleTap }

    /// Whether the finger count on the trackpad matters.
    public var wantsTouches: Bool { middleClick || middleTap }
}

public enum Navigation: String, Sendable, Equatable {
    case back, forward
}

public enum SideButtons {
    /// macOS numbers mouse buttons from 0: left, right, middle, then the two
    /// side buttons. On almost every mouse 3 is the rear one (back) and 4 the
    /// front one (forward).
    public static func navigation(forButton number: Int64, swapped: Bool) -> Navigation? {
        switch number {
        case 3: return swapped ? .forward : .back
        case 4: return swapped ? .back : .forward
        default: return nil
        }
    }
}

/// One finger on the trackpad. Positions are normalised: 0...1 across the
/// surface, whatever its size.
public struct TouchPoint: Sendable, Equatable {
    public let id: Int
    public let x: Double
    public let y: Double

    public init(id: Int, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
}

/// Recognises a three-finger tap from snapshots of the fingers on the trackpad.
///
/// A tap is: exactly three fingers at the peak, all down and up again within a
/// moment, and none of them travelling. Travel is what tells a tap from the
/// three-finger swipes macOS uses for Mission Control and switching Spaces.
public struct TapRecogniser: Sendable {

    public var fingers = 3
    public var maxDuration: TimeInterval = 0.3
    /// In normalised units: 0.04 is about 4% of the trackpad's width.
    public var maxTravel: Double = 0.04

    private var startTime: TimeInterval?
    private var starts: [Int: TouchPoint] = [:]
    private var peak = 0
    private var spoiled = false

    public init() {}

    /// Feed every snapshot of the touching fingers, empty when they have all
    /// lifted. Returns true exactly when a tap has just completed.
    public mutating func update(_ touches: [TouchPoint], at time: TimeInterval) -> Bool {
        if touches.isEmpty {
            defer { reset() }
            guard let start = startTime else { return false }
            return !spoiled && peak == fingers && time - start <= maxDuration
        }

        if startTime == nil { startTime = time }
        peak = max(peak, touches.count)
        if touches.count > fingers { spoiled = true }
        for touch in touches {
            if let first = starts[touch.id] {
                if hypot(touch.x - first.x, touch.y - first.y) > maxTravel { spoiled = true }
            } else {
                starts[touch.id] = touch
            }
        }
        if let start = startTime, time - start > maxDuration { spoiled = true }
        return false
    }

    /// The fingers did something else (pressed the trackpad, say), so when
    /// they lift it must not count as a tap.
    public mutating func spoil() {
        if startTime != nil { spoiled = true }
    }

    public mutating func reset() {
        startTime = nil
        starts = [:]
        peak = 0
        spoiled = false
    }
}
