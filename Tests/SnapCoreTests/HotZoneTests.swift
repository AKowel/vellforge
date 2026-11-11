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
