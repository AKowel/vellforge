import Testing
import CoreGraphics
@testable import SnapCore

@Suite("Hot zone targeting")
struct HotZoneTests {

    let map = HotZoneMap(edgeDepth: 12, cornerSize: 80)
    let display = Display(id: "main",
                          frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                          visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1030))

    @Test("the centre of the screen arms nothing")
    func centreIsInert() {
        #expect(map.target(at: CGPoint(x: 960, y: 540), in: display) == nil)
    }

    @Test("edges arm their own target")
    func edges() {
        #expect(map.target(at: CGPoint(x: 2, y: 540),    in: display) == .left)
        #expect(map.target(at: CGPoint(x: 1918, y: 540), in: display) == .right)
        #expect(map.target(at: CGPoint(x: 960, y: 1078), in: display) == .top)
        #expect(map.target(at: CGPoint(x: 960, y: 2),    in: display) == .bottom)
    }

    @Test("corners beat edges where the regions overlap")
    func cornersWin() {
        // Hard against the left edge, but also within the top corner band.
        #expect(map.target(at: CGPoint(x: 2, y: 1040), in: display) == .topLeft)
        #expect(map.target(at: CGPoint(x: 2, y: 40),   in: display) == .bottomLeft)
        #expect(map.target(at: CGPoint(x: 1918, y: 1040), in: display) == .topRight)
        #expect(map.target(at: CGPoint(x: 1918, y: 40),   in: display) == .bottomRight)
        // Along the top edge but near the left corner.
        #expect(map.target(at: CGPoint(x: 40, y: 1078), in: display) == .topLeft)
    }

    @Test("just inside the edge depth arms, just outside does not")
    func edgeDepthBoundary() {
        #expect(map.target(at: CGPoint(x: 12, y: 540), in: display) == .left)
        #expect(map.target(at: CGPoint(x: 13, y: 540), in: display) == nil)
    }

    @Test("a second display's edges are measured against its own frame")
    func secondaryDisplay() {
        let secondary = Display(id: "second",
                                frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
                                visibleFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        #expect(map.target(at: CGPoint(x: 1922, y: 540), in: secondary) == .left)
        #expect(map.target(at: CGPoint(x: 3838, y: 540), in: secondary) == .right)
        // The shared inner edge is the secondary's left, not its right.
        #expect(map.target(at: CGPoint(x: 1925, y: 540), in: secondary) != .right)
    }

    @Test("a seam between side-by-side displays arms nothing")
    func seamsAreNotEdges() {
        // The arrangement that showed the bug: a 24" to the left, a MacBook
        // in the middle, a full-HD display to the right, tops not aligned.
        let left = Display(id: "left",
                           frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                           visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let laptop = Display(id: "laptop",
                             frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                             visibleFrame: CGRect(x: 0, y: 74, width: 1512, height: 875))
        let right = Display(id: "right",
                            frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
                            visibleFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        let all = [left, laptop, right]

        // Crossing from the laptop into the right-hand display.
        #expect(map.target(at: CGPoint(x: 1506, y: 500), in: laptop, others: all) == nil)
        #expect(map.target(at: CGPoint(x: 1516, y: 500), in: right, others: all) == nil)
        // And from the laptop into the left-hand one.
        #expect(map.target(at: CGPoint(x: 4, y: 500), in: laptop, others: all) == nil)
        #expect(map.target(at: CGPoint(x: -4, y: 500), in: left, others: all) == nil)

        // The outer edges still snap.
        #expect(map.target(at: CGPoint(x: -1918, y: 500), in: left, others: all) == .left)
        #expect(map.target(at: CGPoint(x: 3430, y: 500), in: right, others: all) == .right)
        // Above the laptop's top the right display's left edge is a real
        // edge again: nothing carries on past it there.
        #expect(map.target(at: CGPoint(x: 1514, y: 1000), in: right, others: all) == .topLeft)
        // Low down on the seam nothing arms; only the real bottom edge does.
        #expect(map.target(at: CGPoint(x: 1516, y: 40), in: right, others: all) == nil)
        #expect(map.target(at: CGPoint(x: 1530, y: 2), in: right, others: all) == .bottomLeft)
    }

    @Test("a display stacked on top turns the shared edge into a seam")
    func stackedSeam() {
        let below = display
        let above = Display(id: "above",
                            frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080),
                            visibleFrame: CGRect(x: 0, y: 1080, width: 1920, height: 1055))
        #expect(map.target(at: CGPoint(x: 960, y: 1078), in: below, others: [below, above]) == nil)
        #expect(map.target(at: CGPoint(x: 960, y: 1082), in: above, others: [below, above]) == nil)
        #expect(map.target(at: CGPoint(x: 960, y: 2158), in: above, others: [below, above]) == .top)
    }

    @Test("the top edge maximises, and cycles to a top half")
    func topCycles() {
        #expect(EdgeTarget.top.zone(cycle: 0) == .full)
        #expect(EdgeTarget.top.zone(cycle: 1) == .topHalf)
        #expect(EdgeTarget.top.zone(cycle: 2) == .full, "should wrap")
    }

    @Test("side edges cycle half, third, two-thirds")
    func sideCycles() {
        #expect(EdgeTarget.left.zone(cycle: 0) == .leftHalf)
        #expect(EdgeTarget.left.zone(cycle: 1) == .leftThird)
        #expect(EdgeTarget.left.zone(cycle: 2) == .leftTwoThirds)
        #expect(EdgeTarget.right.zone(cycle: 1) == .rightThird)
    }

    @Test("corners have nothing to cycle through")
    func cornersDoNotCycle() {
        for corner in [EdgeTarget.topLeft, .topRight, .bottomLeft, .bottomRight] {
            #expect(corner.zone(cycle: 0) == corner.zone(cycle: 3))
        }
    }
}
