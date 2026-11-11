import Testing
import CoreGraphics
import Foundation
@testable import BarCore

private func item(_ id: UInt32, x: CGFloat, w: CGFloat = 24, h: CGFloat = 24,
                  name: String? = nil) -> MenuBarItem {
    MenuBarItem(windowID: id, frame: CGRect(x: x, y: 0, width: w, height: h), name: name)
}

@Suite("Menu bar ordering")
struct OrderingTests {

    @Test("visual order runs right to left, the way the eye reads the bar")
    func visualOrder() {
        let items = [item(1, x: 100), item(3, x: 300), item(2, x: 200)]
        #expect(MenuBarLayout.inVisualOrder(items).map(\.windowID) == [3, 2, 1])
    }

    @Test("our own items never appear in our own list")
    func ownItemsExcluded() {
        let items = [item(1, x: 100), item(99, x: 400)]
        #expect(MenuBarLayout.plausible(items, excluding: [99]).map(\.windowID) == [1])
    }

    @Test("zero-size placeholder windows are dropped")
    func placeholdersDropped() {
        let items = [item(1, x: 100), item(2, x: 200, w: 0, h: 0), item(3, x: 300, w: 2, h: 24)]
        // Item 2 has no size and item 3 is a 2pt sliver — both are placeholders.
        #expect(MenuBarLayout.plausible(items).map(\.windowID) == [1])
    }

    @Test("plausible keeps only real-sized items, in visual order")
    func plausibleOrdering() {
        let items = [item(1, x: 100), item(2, x: 500), item(3, x: 300, w: 1, h: 1)]
        #expect(MenuBarLayout.plausible(items).map(\.windowID) == [2, 1])
    }
}

@Suite("Item shape")
struct ShapeTests {

    @Test("a roughly square item reads as an icon")
    func squareIsIcon() {
        #expect(!item(1, x: 0, w: 24, h: 24).looksLikeText)
        #expect(!item(2, x: 0, w: 40, h: 24).looksLikeText)
    }

    @Test("a much wider item reads as a text readout, like a clock")
    func wideIsText() {
        #expect(item(3, x: 0, w: 160, h: 24).looksLikeText)
        #expect(item(4, x: 0, w: 60, h: 24).looksLikeText)
    }

    @Test("a zero-height item does not divide by zero")
    func degenerate() {
        #expect(!item(5, x: 0, w: 40, h: 0).looksLikeText)
    }
}

@Suite("Hiding")
struct HidingTests {

    let items = [item(1, x: 100), item(2, x: 200), item(3, x: 300), item(4, x: 400)]

    @Test("everything left of the separator is what gets hidden")
    func hiddenSet() {
        #expect(MenuBarLayout.hidden(items, leftOfSeparatorX: 340).map(\.windowID) == [3, 2, 1])
    }

    @Test("everything right of the separator stays on show")
    func visibleSet() {
        #expect(MenuBarLayout.alwaysVisible(items, leftOfSeparatorX: 340).map(\.windowID) == [4])
    }

    @Test("hidden and visible together account for every item, with no overlap")
    func partitionIsComplete() {
        for x in stride(from: CGFloat(0), through: 600, by: 50) {
            let hidden = MenuBarLayout.hidden(items, leftOfSeparatorX: x)
            let visible = MenuBarLayout.alwaysVisible(items, leftOfSeparatorX: x)
            #expect(hidden.count + visible.count == items.count, "lost an item at x=\(x)")
            #expect(Set(hidden.map(\.windowID)).isDisjoint(with: Set(visible.map(\.windowID))),
                    "an item was both hidden and visible at x=\(x)")
        }
    }

    @Test("a separator at the far left hides nothing")
    func separatorAtEdge() {
        #expect(MenuBarLayout.hidden(items, leftOfSeparatorX: 0).isEmpty)
    }
}

@Suite("Click targeting")
struct ClickTests {
    @Test("the click point is the centre of the item")
    func clickPoint() {
        let it = MenuBarItem(windowID: 1, frame: CGRect(x: 100, y: 0, width: 30, height: 24))
        #expect(it.clickPoint == CGPoint(x: 115, y: 12))
    }
}
