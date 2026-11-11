import Testing
import CoreGraphics
@testable import SnapCore

@Suite("Display remapping")
struct DisplayMappingTests {

    let laptop = Display(id: "laptop",
                         frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                         visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
    let monitor = Display(id: "monitor",
                          frame: CGRect(x: 1440, y: 0, width: 2880, height: 1800),
                          visibleFrame: CGRect(x: 1440, y: 0, width: 2880, height: 1800))

    @Test("a maximised window stays maximised on the destination")
    func maximisedStaysMaximised() {
        let full = Zone.full.resolve(in: laptop.visibleFrame)
        #expect(laptop.remap(full, to: monitor) == monitor.visibleFrame)
    }

    @Test("a right half stays a right half, scaled to the new display")
    func rightHalfSurvives() {
        let half = Zone.rightHalf.resolve(in: laptop.visibleFrame)
        let moved = laptop.remap(half, to: monitor)
        #expect(moved == Zone.rightHalf.resolve(in: monitor.visibleFrame))
    }

    @Test("a top-left quarter keeps its corner, not its pixel size")
    func cornerIsPreserved() {
        let quarter = Zone.topLeft.resolve(in: monitor.visibleFrame)
        let moved = monitor.remap(quarter, to: laptop)
        #expect(moved == Zone.topLeft.resolve(in: laptop.visibleFrame))
        #expect(moved.width < quarter.width, "should scale down onto the smaller screen")
    }

    @Test("remapping is reversible")
    func roundTrips() {
        let rect = CGRect(x: 200, y: 150, width: 600, height: 400)
        let there = laptop.remap(rect, to: monitor)
        let back = monitor.remap(there, to: laptop)
        #expect(abs(back.minX - rect.minX) < 0.001)
        #expect(abs(back.minY - rect.minY) < 0.001)
        #expect(abs(back.width - rect.width) < 0.001)
        #expect(abs(back.height - rect.height) < 0.001)
    }

    @Test("next display wraps around and follows physical order")
    func nextWraps() {
        let displays = [monitor, laptop]   // deliberately out of physical order
        #expect(displays.next(after: laptop)?.id == "monitor")
        #expect(displays.next(after: monitor)?.id == "laptop", "should wrap")
        #expect(displays.next(after: laptop, reverse: true)?.id == "monitor")
    }

    @Test("next display is nil with only one screen")
    func singleDisplay() {
        #expect([laptop].next(after: laptop) == nil)
    }
}
