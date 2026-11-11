import Testing
import CoreGraphics
@testable import SnapCore

@Suite("Layout presets")
struct LayoutTests {

    let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)

    @Test("every preset's cells tile the screen exactly")
    func presetsTileExactly() {
        for layout in Layout.presets {
            let rects = layout.cells.map { $0.resolve(in: screen) }
            let area = rects.reduce(0) { $0 + $1.width * $1.height }
            #expect(abs(area - screen.width * screen.height) < 1,
                    "\(layout.name) covers \(area), expected \(screen.width * screen.height)")
        }
    }

    @Test("no preset has overlapping cells")
    func presetsDoNotOverlap() {
        for layout in Layout.presets {
            let rects = layout.cells.map { $0.resolve(in: screen) }
            for (i, a) in rects.enumerated() {
                for b in rects[(i + 1)...] {
                    let overlap = a.intersection(b)
                    #expect(overlap.isEmpty || overlap.width < 0.001 || overlap.height < 0.001,
                            "\(layout.name) overlaps: \(a) and \(b)")
                }
            }
        }
    }

    @Test("every preset has a unique id and at least two cells")
    func presetsAreWellFormed() {
        let ids = Layout.presets.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate layout ids")
        for layout in Layout.presets {
            #expect(layout.cells.count >= 2, "\(layout.name) needs at least two cells")
        }
    }
}

@Suite("Layout bar geometry")
struct LayoutBarTests {

    let bar = LayoutBar()
    let display = Display(id: "main",
                          frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                          visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055))

    @Test("the bar is centred horizontally and hangs from the top")
    func barPosition() {
        let frame = bar.frame(layoutCount: 6, in: display)
        #expect(abs(frame.midX - display.frame.midX) < 0.001)
        #expect(frame.maxY == display.visibleFrame.maxY - bar.topMargin)
        #expect(frame.maxY < display.frame.maxY, "must sit below the menu bar")
    }

    @Test("tiles are evenly spaced and fit inside the bar")
    func tileLayout() {
        let frame = bar.frame(layoutCount: 4, in: display)
        let tiles = bar.tiles(layoutCount: 4, in: display)
        #expect(tiles.count == 4)
        #expect(tiles[0].minX == frame.minX + bar.padding)
        #expect(abs(tiles[3].maxX - (frame.maxX - bar.padding)) < 0.001)
        for tile in tiles { #expect(frame.contains(tile)) }
        // Even spacing.
        let gaps = zip(tiles.dropFirst(), tiles).map { $0.minX - $1.maxX }
        for gap in gaps { #expect(abs(gap - bar.tileGap) < 0.001) }
    }

    @Test("a tile's cells stay inside it")
    func cellsFitTile() {
        let tiles = bar.tiles(layoutCount: 6, in: display)
        for (index, layout) in Layout.presets.enumerated() {
            for cell in bar.cells(of: layout, in: tiles[index]) {
                #expect(tiles[index].insetBy(dx: -0.5, dy: -0.5).contains(cell),
                        "\(layout.name) cell escaped its tile")
            }
        }
    }

    @Test("hit testing finds the cell under the cursor")
    func hitTesting() {
        let layouts = Layout.presets
        let tiles = bar.tiles(layoutCount: layouts.count, in: display)

        // Left cell of the halves tile (index 0).
        let halvesLeft = bar.cells(of: layouts[0], in: tiles[0])[0]
        #expect(bar.hitTest(CGPoint(x: halvesLeft.midX, y: halvesLeft.midY),
                            layouts: layouts, in: display)
                == LayoutHit(layoutIndex: 0, cellIndex: 0))

        // Right cell of the same tile.
        let halvesRight = bar.cells(of: layouts[0], in: tiles[0])[1]
        #expect(bar.hitTest(CGPoint(x: halvesRight.midX, y: halvesRight.midY),
                            layouts: layouts, in: display)
                == LayoutHit(layoutIndex: 0, cellIndex: 1))

        // Middle cell of the thirds tile (index 1).
        let thirdsMiddle = bar.cells(of: layouts[1], in: tiles[1])[1]
        #expect(bar.hitTest(CGPoint(x: thirdsMiddle.midX, y: thirdsMiddle.midY),
                            layouts: layouts, in: display)
                == LayoutHit(layoutIndex: 1, cellIndex: 1))
    }

    @Test("the gap between cells still resolves to the nearest cell")
    func gapsAreNotDead() {
        let layouts = Layout.presets
        let tiles = bar.tiles(layoutCount: layouts.count, in: display)
        let cells = bar.cells(of: layouts[0], in: tiles[0])
        // Exactly between the two halves.
        let between = CGPoint(x: (cells[0].maxX + cells[1].minX) / 2, y: tiles[0].midY)
        let hit = bar.hitTest(between, layouts: layouts, in: display)
        #expect(hit != nil, "a point in the cell gap must still hit something")
        #expect(hit?.layoutIndex == 0)
    }

    @Test("points outside the bar hit nothing")
    func missesReturnNil() {
        #expect(bar.hitTest(CGPoint(x: 960, y: 500),
                            layouts: Layout.presets, in: display) == nil)
        #expect(bar.hitTest(CGPoint(x: 5, y: 1050),
                            layouts: Layout.presets, in: display) == nil)
    }

    @Test("the bar reveals near the top and not elsewhere")
    func revealRegion() {
        #expect(bar.shouldReveal(at: CGPoint(x: 960, y: 1070), in: display))
        #expect(bar.shouldReveal(at: CGPoint(x: 960, y: 940), in: display))
        #expect(!bar.shouldReveal(at: CGPoint(x: 960, y: 500), in: display))
    }

    @Test("the bar centres on a secondary display, not the primary")
    func secondaryDisplay() {
        let secondary = Display(id: "second",
                                frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
                                visibleFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        let frame = bar.frame(layoutCount: 6, in: secondary)
        #expect(abs(frame.midX - secondary.frame.midX) < 0.001)
        #expect(frame.minX > 1920)
    }
}
