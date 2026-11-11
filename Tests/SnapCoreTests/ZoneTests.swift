import Testing
import CoreGraphics
@testable import SnapCore

@Suite("Zone resolution")
struct ZoneTests {

    /// A clean synthetic screen. Real visible frames are odd sizes because of
    /// the menu bar and Dock; round numbers make failures readable.
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)

    @Test("left half hugs the left edge at full height")
    func leftHalf() {
        #expect(Zone.leftHalf.resolve(in: screen)
                == CGRect(x: 0, y: 0, width: 500, height: 1000))
    }

    @Test("right half is offset by half the width")
    func rightHalf() {
        #expect(Zone.rightHalf.resolve(in: screen)
                == CGRect(x: 500, y: 0, width: 500, height: 1000))
    }

    /// The one that catches an inverted y-axis: in AppKit the *top* half has the
    /// *higher* origin, because y grows upward.
    @Test("top half sits at the higher y origin, not the lower")
    func topHalfIsAbove() {
        let top = Zone.topHalf.resolve(in: screen)
        let bottom = Zone.bottomHalf.resolve(in: screen)
        #expect(top == CGRect(x: 0, y: 500, width: 1000, height: 500))
        #expect(bottom == CGRect(x: 0, y: 0, width: 1000, height: 500))
        #expect(top.minY > bottom.minY)
    }

    @Test("quarters tile the screen without overlap or gaps")
    func quartersTileExactly() {
        let quarters = [Zone.topLeft, .topRight, .bottomLeft, .bottomRight]
            .map { $0.resolve(in: screen) }

        #expect(quarters.reduce(0) { $0 + $1.width * $1.height } == screen.width * screen.height)
        for (i, a) in quarters.enumerated() {
            for b in quarters[(i + 1)...] {
                #expect(a.intersection(b).isEmpty, "quarters \(a) and \(b) overlap")
            }
        }
    }

    @Test("thirds cover the full width")
    func thirdsCoverWidth() {
        let thirds = [Zone.leftThird, .centerThird, .rightThird].map { $0.resolve(in: screen) }
        #expect(abs(thirds.reduce(0) { $0 + $1.width } - screen.width) < 0.0001)
        #expect(thirds[0].minX == 0)
        #expect(abs(thirds[2].maxX - screen.width) < 0.0001)
    }

    // MARK: Multi-display

    @Test("zones respect a display offset to the right of the primary")
    func secondaryDisplayToTheRight() {
        let secondary = CGRect(x: 1920, y: 0, width: 1000, height: 1000)
        #expect(Zone.leftHalf.resolve(in: secondary)
                == CGRect(x: 1920, y: 0, width: 500, height: 1000))
    }

    /// A display stacked *above* the primary is where naive maths usually breaks.
    @Test("zones respect a display stacked above the primary")
    func secondaryDisplayAbove() {
        let above = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        let top = Zone.topHalf.resolve(in: above)
        #expect(top == CGRect(x: 0, y: 1620, width: 1920, height: 540))
        #expect(top.maxY == above.maxY, "top half must reach the top of its own display")
    }

    @Test("displays of differing heights each resolve against their own frame")
    func mismatchedHeights() {
        let laptop = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let monitor = CGRect(x: 1440, y: 0, width: 2560, height: 1440)
        #expect(Zone.maximizeZone.resolve(in: laptop) == laptop)
        #expect(Zone.maximizeZone.resolve(in: monitor) == monitor)
    }

    // MARK: Gaps

    @Test("a gap insets every edge")
    func gapInsets() {
        let r = Zone.leftHalf.resolve(in: screen, gap: 10)
        #expect(r == CGRect(x: 10, y: 10, width: 480, height: 980))
    }

    @Test("an absurd gap cannot invert the rect")
    func gapCannotInvert() {
        let r = Zone.topLeft.resolve(in: screen, gap: 10_000)
        #expect(r.width > 0)
        #expect(r.height > 0)
    }
}

extension Zone {
    /// Alias so the intent reads clearly in the mismatched-height test.
    static var maximizeZone: Zone { .full }
}

@Suite("Zone capture")
struct ZoneCaptureTests {

    let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    @Test("capturing then resolving returns the original rect")
    func roundTrips() {
        let rects = [
            CGRect(x: 0, y: 0, width: 800, height: 1000),
            CGRect(x: 240, y: 130, width: 620, height: 410),
            CGRect(x: 0, y: 0, width: 1600, height: 1000),
        ]
        for rect in rects {
            let zone = Zone(rect: rect, in: screen)
            let back = zone.resolve(in: screen)
            #expect(abs(back.minX - rect.minX) < 0.001)
            #expect(abs(back.minY - rect.minY) < 0.001)
            #expect(abs(back.width - rect.width) < 0.001)
            #expect(abs(back.height - rect.height) < 0.001)
        }
    }

    @Test("a captured half is recognisably the half zone")
    func capturesNamedZones() {
        let captured = Zone(rect: Zone.rightHalf.resolve(in: screen), in: screen)
        #expect(abs(captured.x - 0.5) < 0.001)
        #expect(abs(captured.width - 0.5) < 0.001)
        #expect(abs(captured.y) < 0.001)
        #expect(abs(captured.height - 1) < 0.001)
    }

    @Test("a layout captured on a big screen scales onto a small one")
    func scalesAcrossScreens() {
        let big = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let small = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let zone = Zone(rect: Zone.topRight.resolve(in: big), in: big)
        #expect(zone.resolve(in: small) == Zone.topRight.resolve(in: small))
    }

    @Test("capture handles a display with a non-zero origin")
    func offsetDisplay() {
        let secondary = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let rect = Zone.leftThird.resolve(in: secondary)
        let zone = Zone(rect: rect, in: secondary)
        #expect(abs(zone.x) < 0.001)
        #expect(abs(zone.width - 1.0 / 3.0) < 0.001)
    }
}
