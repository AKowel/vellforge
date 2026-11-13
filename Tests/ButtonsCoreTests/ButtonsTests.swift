import Foundation
import Testing
@testable import ButtonsCore

@Suite("Side buttons")
struct SideButtonTests {

    @Test("button 3 is back and 4 is forward, unless swapped")
    func mapping() {
        #expect(SideButtons.navigation(forButton: 3, swapped: false) == .back)
        #expect(SideButtons.navigation(forButton: 4, swapped: false) == .forward)
        #expect(SideButtons.navigation(forButton: 3, swapped: true) == .forward)
        #expect(SideButtons.navigation(forButton: 4, swapped: true) == .back)
    }

    @Test("left, right and middle are never touched")
    func ordinaryButtonsPassThrough() {
        for button: Int64 in [0, 1, 2, 5, 6] {
            #expect(SideButtons.navigation(forButton: button, swapped: false) == nil)
        }
    }

    @Test("settings know when there's nothing to do")
    func noOp() {
        #expect(!ButtonSettings.standard.isNoOp)
        #expect(!ButtonSettings.standard.middleTap, "tapping is opt-in")
        let off = ButtonSettings(sideButtons: false, middleClick: false, middleTap: false)
        #expect(off.isNoOp)
        #expect(!off.wantsTouches)
    }
}

@Suite("Three-finger tap")
struct TapRecogniserTests {

    private func fingers(_ n: Int, dx: Double = 0) -> [TouchPoint] {
        (0..<n).map { TouchPoint(id: $0, x: 0.3 + Double($0) * 0.1 + dx, y: 0.5) }
    }

    @Test("three fingers down and up quickly, without moving, is a tap")
    func tap() {
        var r = TapRecogniser()
        let result1 = r.update(fingers(3), at: 0)
        #expect(!result1)
        let result2 = r.update(fingers(3), at: 0.05)
        #expect(!result2)
        let result3 = r.update([], at: 0.12)
        #expect(result3)
    }

    @Test("fingers landing one at a time still count")
    func staggered() {
        var r = TapRecogniser()
        _ = r.update(fingers(1), at: 0)
        _ = r.update(fingers(2), at: 0.02)
        _ = r.update(fingers(3), at: 0.04)
        _ = r.update(fingers(2), at: 0.10)
        let result4 = r.update([], at: 0.14)
        #expect(result4)
    }

    @Test("a three-finger swipe is not a tap")
    func swipe() {
        var r = TapRecogniser()
        _ = r.update(fingers(3), at: 0)
        _ = r.update(fingers(3, dx: 0.2), at: 0.1)
        let result5 = r.update([], at: 0.15)
        #expect(!result5)
    }

    @Test("holding too long is not a tap")
    func slow() {
        var r = TapRecogniser()
        _ = r.update(fingers(3), at: 0)
        _ = r.update(fingers(3), at: 0.5)
        let result6 = r.update([], at: 0.6)
        #expect(!result6)
    }

    @Test("two or four fingers are not a three-finger tap")
    func wrongCount() {
        var two = TapRecogniser()
        _ = two.update(fingers(2), at: 0)
        let result7 = two.update([], at: 0.1)
        #expect(!result7)

        var four = TapRecogniser()
        _ = four.update(fingers(4), at: 0)
        _ = four.update(fingers(3), at: 0.05)
        let result8 = four.update([], at: 0.1)
        #expect(!result8)
    }

    @Test("a three-finger press of the trackpad is a click, not also a tap")
    func spoiledByClick() {
        var r = TapRecogniser()
        _ = r.update(fingers(3), at: 0)
        r.spoil()
        let result9 = r.update([], at: 0.1)
        #expect(!result9)
        // And the next one starts clean.
        _ = r.update(fingers(3), at: 1)
        let result10 = r.update([], at: 1.1)
        #expect(result10)
    }

    @Test("lifting with no fingers down first does nothing")
    func emptyStart() {
        var r = TapRecogniser()
        let result11 = r.update([], at: 0)
        #expect(!result11)
    }
}
