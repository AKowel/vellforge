import Testing
import CoreGraphics
@testable import SnapCore

@Suite("Coordinate space conversion")
struct CoordinateSpaceTests {

    let primaryMaxY: CGFloat = 1080

    @Test("converting to Accessibility flips the y origin")
    func flipsY() {
        let appKit = CGRect(x: 100, y: 200, width: 300, height: 400)
        let ax = CoordinateSpace.toAccessibility(appKit, primaryMaxY: primaryMaxY)
        // AppKit maxY is 600, so the top edge sits 1080 - 600 = 480 from the top.
        #expect(ax == CGRect(x: 100, y: 480, width: 300, height: 400))
    }

    @Test("the transform is its own inverse")
    func roundTrips() {
        let rects = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 100, y: 200, width: 300, height: 400),
            CGRect(x: -1440, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: 1080, width: 1920, height: 1080),
        ]
        for rect in rects {
            let there = CoordinateSpace.toAccessibility(rect, primaryMaxY: primaryMaxY)
            let back = CoordinateSpace.toAppKit(there, primaryMaxY: primaryMaxY)
            #expect(back == rect, "round trip failed for \(rect)")
        }
    }

    /// In Accessibility coordinates a display above the primary has *negative*
    /// y. If this ever returns a positive number, windows will land off-screen.
    @Test("a display above the primary yields negative y")
    func displayAboveIsNegative() {
        let above = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        let ax = CoordinateSpace.toAccessibility(above, primaryMaxY: primaryMaxY)
        #expect(ax.minY == -1080)
    }

    @Test("the primary screen itself maps to the origin")
    func primaryMapsToOrigin() {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let ax = CoordinateSpace.toAccessibility(primary, primaryMaxY: primaryMaxY)
        #expect(ax == CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    @Test("centring preserves size and lands on the midpoint")
    func centring() {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let r = CoordinateSpace.centered(size: CGSize(width: 400, height: 200), in: vf)
        #expect(r == CGRect(x: 300, y: 400, width: 400, height: 200))
        #expect(r.center == vf.center)
    }
}

@Suite("Display lookup")
struct DisplayTests {
    let laptop = Display(id: "laptop",
                         frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                         visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
    let external = Display(id: "external",
                           frame: CGRect(x: 1440, y: 0, width: 2560, height: 1440),
                           visibleFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1415))

    @Test("a point inside a display finds that display")
    func hit() {
        let displays = [laptop, external]
        #expect(displays.containing(CGPoint(x: 200, y: 200))?.id == "laptop")
        #expect(displays.containing(CGPoint(x: 2000, y: 700))?.id == "external")
    }

    @Test("a point outside every display falls back to the nearest")
    func fallbackToNearest() {
        let displays = [laptop, external]
        // Far off the left edge — nearest centre is the laptop.
        #expect(displays.containing(CGPoint(x: -5000, y: 400))?.id == "laptop")
        // Far off the right edge — nearest centre is the external.
        #expect(displays.containing(CGPoint(x: 9000, y: 700))?.id == "external")
    }
}
