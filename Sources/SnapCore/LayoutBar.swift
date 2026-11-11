import CoreGraphics

/// Which cell of which layout the cursor is over.
public struct LayoutHit: Equatable, Sendable {
    public let layoutIndex: Int
    public let cellIndex: Int

    public init(layoutIndex: Int, cellIndex: Int) {
        self.layoutIndex = layoutIndex
        self.cellIndex = cellIndex
    }
}

/// Geometry for the layout chooser that drops down from the top of the screen
/// during a drag.
///
/// Pure maths, kept out of the view layer so hit-testing can be tested directly
/// — getting this wrong means cells that highlight but drop somewhere else.
public struct LayoutBar: Sendable {

    public var tileSize: CGSize
    public var tileGap: CGFloat
    public var padding: CGFloat
    public var cellGap: CGFloat
    /// Distance below the top of the usable area where the bar sits.
    public var topMargin: CGFloat
    /// How far from the top of the display a drag must reach to reveal the bar.
    public var revealDepth: CGFloat

    public init(tileSize: CGSize = CGSize(width: 116, height: 74),
                tileGap: CGFloat = 10,
                padding: CGFloat = 14,
                cellGap: CGFloat = 3,
                topMargin: CGFloat = 8,
                revealDepth: CGFloat = 150) {
        self.tileSize = tileSize
        self.tileGap = tileGap
        self.padding = padding
        self.cellGap = cellGap
        self.topMargin = topMargin
        self.revealDepth = revealDepth
    }

    public func shouldReveal(at point: CGPoint, in display: Display) -> Bool {
        point.y >= display.frame.maxY - revealDepth
            && point.x >= display.frame.minX
            && point.x <= display.frame.maxX
    }

    /// The bar itself, centred horizontally and hanging below the menu bar.
    public func frame(layoutCount: Int, in display: Display) -> CGRect {
        guard layoutCount > 0 else { return .zero }
        let width = CGFloat(layoutCount) * tileSize.width
            + CGFloat(layoutCount - 1) * tileGap
            + padding * 2
        let height = tileSize.height + padding * 2
        return CGRect(x: display.frame.midX - width / 2,
                      y: display.visibleFrame.maxY - topMargin - height,
                      width: width,
                      height: height)
    }

    /// One tile per layout, left to right inside the bar.
    public func tiles(layoutCount: Int, in display: Display) -> [CGRect] {
        let bar = frame(layoutCount: layoutCount, in: display)
        return (0..<layoutCount).map { index in
            CGRect(x: bar.minX + padding + CGFloat(index) * (tileSize.width + tileGap),
                   y: bar.minY + padding,
                   width: tileSize.width,
                   height: tileSize.height)
        }
    }

    /// Each tile is a miniature screen, so a cell is just its zone resolved
    /// against the tile — the same maths that places the real window.
    public func cells(of layout: Layout, in tile: CGRect) -> [CGRect] {
        layout.cells.map { $0.resolve(in: tile, gap: Double(cellGap)) }
    }

    public func hitTest(_ point: CGPoint,
                        layouts: [Layout],
                        in display: Display) -> LayoutHit? {
        let tileFrames = tiles(layoutCount: layouts.count, in: display)
        for (layoutIndex, tile) in tileFrames.enumerated() {
            // Grow the tile slightly so the gaps between cells stay hittable
            // rather than producing dead pixels mid-drag.
            guard tile.insetBy(dx: -tileGap / 2, dy: -tileGap / 2).contains(point)
            else { continue }

            let cellFrames = cells(of: layouts[layoutIndex], in: tile)
            // Nearest cell centre, so a point in a gap still resolves.
            var best: (index: Int, distance: CGFloat)?
            for (cellIndex, cell) in cellFrames.enumerated() {
                if cell.contains(point) { return LayoutHit(layoutIndex: layoutIndex, cellIndex: cellIndex) }
                let dx = cell.midX - point.x, dy = cell.midY - point.y
                let distance = dx * dx + dy * dy
                if best == nil || distance < best!.distance {
                    best = (cellIndex, distance)
                }
            }
            if let best { return LayoutHit(layoutIndex: layoutIndex, cellIndex: best.index) }
        }
        return nil
    }
}
