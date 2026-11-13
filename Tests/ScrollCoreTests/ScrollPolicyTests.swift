import Foundation
import Testing
@testable import ScrollCore

@Suite("Scroll source classification")
struct ScrollSourceTests {

    // Phase values as CoreGraphics reports them: 1 began, 2 changed, 4 ended,
    // 128 may-begin; momentum 1 begin, 2 continue, 3 end.

    @Test("a notched wheel is a mouse, whatever else the event says")
    func discreteIsMouse() {
        #expect(ScrollSource.classify(isContinuous: false) == .mouse)
        #expect(ScrollSource.classify(isContinuous: false, scrollPhase: 2) == .mouse)
    }

    @Test("a gesture with a phase is a trackpad")
    func gestureIsTrackpad() {
        for phase: Int64 in [1, 2, 4, 128] {
            #expect(ScrollSource.classify(isContinuous: true, scrollPhase: phase) == .trackpad)
        }
    }

    @Test("momentum after the fingers lift still counts as the trackpad")
    func momentumIsTrackpad() {
        for momentum: Int64 in [1, 2, 3] {
            #expect(ScrollSource.classify(isContinuous: true, scrollPhase: 0,
                                          momentumPhase: momentum) == .trackpad)
        }
    }

    @Test("a smooth wheel (continuous, no phase) is a mouse, not a trackpad")
    func smoothWheelIsMouse() {
        // Logitech MX Master: continuous deltas, never a gesture phase. This
        // was taken for a trackpad, so "invert mouse" did nothing to it.
        #expect(ScrollSource.classify(isContinuous: true) == .mouse)
    }
}

@Suite("Scroll policy")
struct ScrollPolicyTests {

    @Test("the default inverts the mouse and leaves the trackpad alone")
    func defaultSettings() {
        let s = ScrollSettings.standard
        #expect(ScrollPolicy.shouldInvertVertical(source: .mouse, settings: s))
        #expect(!ScrollPolicy.shouldInvertVertical(source: .trackpad, settings: s))
    }

    @Test("each device is controlled independently")
    func independentDevices() {
        let trackpadOnly = ScrollSettings(invertMouse: false, invertTrackpad: true)
        #expect(!ScrollPolicy.shouldInvertVertical(source: .mouse, settings: trackpadOnly))
        #expect(ScrollPolicy.shouldInvertVertical(source: .trackpad, settings: trackpadOnly))

        let both = ScrollSettings(invertMouse: true, invertTrackpad: true)
        #expect(ScrollPolicy.shouldInvertVertical(source: .mouse, settings: both))
        #expect(ScrollPolicy.shouldInvertVertical(source: .trackpad, settings: both))
    }

    @Test("horizontal inversion only applies where vertical already does")
    func horizontalFollowsVertical() {
        // Horizontal is on, but the mouse is not being inverted at all.
        let s = ScrollSettings(invertMouse: false, invertTrackpad: true, invertHorizontal: true)
        #expect(!ScrollPolicy.shouldInvertHorizontal(source: .mouse, settings: s))
        #expect(ScrollPolicy.shouldInvertHorizontal(source: .trackpad, settings: s))
    }

    @Test("horizontal stays untouched unless explicitly enabled")
    func horizontalOffByDefault() {
        let s = ScrollSettings.standard
        #expect(!ScrollPolicy.shouldInvertHorizontal(source: .mouse, settings: s))
    }

    @Test("a decision covers both axes in one call")
    func decisions() {
        let s = ScrollSettings(invertMouse: true, invertTrackpad: false, invertHorizontal: true)
        let mouse = ScrollPolicy.decide(isContinuous: false, settings: s)
        #expect(mouse.invertVertical)
        #expect(mouse.invertHorizontal)
        #expect(!mouse.isIdentity)

        let trackpad = ScrollPolicy.decide(isContinuous: true, scrollPhase: 2, settings: s)
        #expect(!trackpad.invertVertical)
        #expect(!trackpad.invertHorizontal)
        #expect(trackpad.isIdentity, "an untouched device must produce no change at all")

        let smoothWheel = ScrollPolicy.decide(isContinuous: true, settings: s)
        #expect(smoothWheel.invertVertical, "a smooth wheel follows the mouse setting")
    }

    @Test("turning everything off is recognised as doing nothing")
    func noOpDetection() {
        #expect(ScrollSettings(invertMouse: false, invertTrackpad: false).isNoOp)
        #expect(!ScrollSettings.standard.isNoOp)
        // Horizontal alone must not make it look like there is work to do.
        #expect(ScrollSettings(invertMouse: false, invertTrackpad: false,
                               invertHorizontal: true).isNoOp)
    }

    @Test("settings survive a round trip through storage")
    func codable() throws {
        let s = ScrollSettings(invertMouse: false, invertTrackpad: true, invertHorizontal: true)
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(ScrollSettings.self, from: data) == s)
    }
}

@Suite("Effective direction")
struct EffectiveDirectionTests {

    @Test("with the system set to natural, the default gives phone-like trackpad and classic mouse")
    func defaultWithNaturalOn() {
        let s = ScrollSettings.standard
        #expect(EffectiveDirection.resolve(source: .trackpad, systemNatural: true, settings: s) == .natural)
        #expect(EffectiveDirection.resolve(source: .mouse, systemNatural: true, settings: s) == .traditional)
        #expect(EffectiveDirection.isConventional(systemNatural: true, settings: s))
    }

    /// The trap: Vellscroll only flips, so the same settings invert wholesale
    /// when the system switch changes underneath them.
    @Test("the same settings give the opposite result if the system switch is off")
    func defaultWithNaturalOff() {
        let s = ScrollSettings.standard
        #expect(EffectiveDirection.resolve(source: .trackpad, systemNatural: false, settings: s) == .traditional)
        #expect(EffectiveDirection.resolve(source: .mouse, systemNatural: false, settings: s) == .natural)
        #expect(!EffectiveDirection.isConventional(systemNatural: false, settings: s),
                "this is exactly backwards and the app must be able to say so")
    }

    @Test("the suggested fix produces the conventional arrangement either way")
    func suggestedFixAlwaysWorks() {
        for systemNatural in [true, false] {
            let fixed = EffectiveDirection.conventionalSettings(systemNatural: systemNatural)
            #expect(EffectiveDirection.isConventional(systemNatural: systemNatural, settings: fixed),
                    "failed for systemNatural=\(systemNatural)")
            #expect(EffectiveDirection.resolve(source: .trackpad, systemNatural: systemNatural,
                                               settings: fixed) == .natural)
            #expect(EffectiveDirection.resolve(source: .mouse, systemNatural: systemNatural,
                                               settings: fixed) == .traditional)
        }
    }

    @Test("the suggested fix preserves the horizontal preference")
    func fixKeepsHorizontal() {
        #expect(EffectiveDirection.conventionalSettings(systemNatural: true,
                                                        keepingHorizontal: true).invertHorizontal)
        #expect(!EffectiveDirection.conventionalSettings(systemNatural: true).invertHorizontal)
    }

    @Test("inverting both devices flips both, never just one")
    func invertingBoth() {
        let both = ScrollSettings(invertMouse: true, invertTrackpad: true)
        #expect(EffectiveDirection.resolve(source: .trackpad, systemNatural: true, settings: both) == .traditional)
        #expect(EffectiveDirection.resolve(source: .mouse, systemNatural: true, settings: both) == .traditional)
    }
}
