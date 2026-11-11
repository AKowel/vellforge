import AppKit
import SnapCore

/// The layout chooser that drops from the top of the screen mid-drag.
///
/// Click-through like the preview: hit-testing is done against the global cursor
/// position, so the bar never needs to receive events and can never interrupt
/// the drag it is describing.
@MainActor
final class LayoutBarOverlay {

    private let window: NSWindow
    private let barView = LayoutBarView()
    private var isVisible = false
    private var shownDisplay: String?

    let geometry = LayoutBar()
    let layouts = Layout.presets

    init() {
        window = NSWindow(contentRect: .zero,
                          styleMask: .borderless,
                          backing: .buffered,
                          defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        // Above the window being dragged, which macOS raises during a drag.
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                     .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = barView
        window.alphaValue = 0
    }

    func show(in display: Display) {
        let frame = geometry.frame(layoutCount: layouts.count, in: display)
        barView.configure(layouts: layouts, geometry: geometry,
                          display: display, origin: frame.origin)

        guard !isVisible || shownDisplay != display.id else { return }
        shownDisplay = display.id

        if isVisible {
            window.setFrame(frame, display: true)
            return
        }
        isVisible = true

        // Slide down from just above its resting place — the bar should read as
        // arriving from off-screen, the way the menu bar's own overlays do.
        var start = frame
        start.origin.y += 12
        window.setFrame(start, display: false)
        window.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(frame, display: true)
        }
    }

    func highlight(_ hit: LayoutHit?) {
        barView.highlight = hit
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        shownDisplay = nil
        barView.highlight = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isVisible else { return }
                self.window.orderOut(nil)
            }
        })
    }

    func dismissImmediately() {
        isVisible = false
        shownDisplay = nil
        barView.highlight = nil
        window.alphaValue = 0
        window.orderOut(nil)
    }
}

// MARK: - Drawing

private final class LayoutBarView: NSView {

    private struct Tile {
        let rect: CGRect
        let cells: [CGRect]
    }

    private var tiles: [Tile] = []

    var highlight: LayoutHit? {
        didSet { if oldValue != highlight { needsDisplay = true } }
    }

    override var isFlipped: Bool { false }
    override var allowsVibrancy: Bool { true }

    /// Converts screen-space geometry into this view's own coordinates.
    func configure(layouts: [Layout], geometry: LayoutBar,
                   display: Display, origin: CGPoint) {
        let screenTiles = geometry.tiles(layoutCount: layouts.count, in: display)
        tiles = zip(layouts, screenTiles).map { layout, tile in
            Tile(rect: tile.offsetBy(dx: -origin.x, dy: -origin.y),
                 cells: geometry.cells(of: layout, in: tile)
                                .map { $0.offsetBy(dx: -origin.x, dy: -origin.y) })
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Panel
        let panel = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        panel.fill()
        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        panel.lineWidth = 1
        panel.stroke()

        for (layoutIndex, tile) in tiles.enumerated() {
            let isActiveTile = highlight?.layoutIndex == layoutIndex

            let tilePath = NSBezierPath(roundedRect: tile.rect.insetBy(dx: -4, dy: -4),
                                        xRadius: 8, yRadius: 8)
            if isActiveTile {
                NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
                tilePath.fill()
            }

            for (cellIndex, cell) in tile.cells.enumerated() {
                let path = NSBezierPath(roundedRect: cell, xRadius: 3, yRadius: 3)
                let isHot = isActiveTile && highlight?.cellIndex == cellIndex

                if isHot {
                    NSColor.controlAccentColor.setFill()
                } else {
                    NSColor.secondaryLabelColor.withAlphaComponent(0.22).setFill()
                }
                path.fill()

                if isHot {
                    NSColor.controlAccentColor.blended(withFraction: 0.3, of: .black)?.setStroke()
                    path.lineWidth = 1
                    path.stroke()
                }
            }
        }
    }
}
