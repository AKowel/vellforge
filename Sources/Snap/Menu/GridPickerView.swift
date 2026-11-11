import AppKit
import SnapCore

/// A clickable grid embedded in the menu.
///
/// Earns its place by exposing arbitrary regions — a 4×2 block of a 6×4 grid
/// has no name and no sensible shortcut, but is one drag here. It also gives
/// people who never learn the hotkeys somewhere obvious to start.
@MainActor
final class GridPickerView: NSView {

    var spec = GridSpec(columns: 6, rows: 4) { didSet { invalidateIntrinsicContentSize() } }
    var onSelect: ((Zone) -> Void)?

    private var selection: GridSelection?
    private var isDragging = false

    private let cell = CGSize(width: 26, height: 21)
    private let gap: CGFloat = 3
    private let inset: CGFloat = 12
    private let labelHeight: CGFloat = 16

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(spec.columns) * cell.width
                    + CGFloat(spec.columns - 1) * gap + inset * 2,
               height: CGFloat(spec.rows) * cell.height
                    + CGFloat(spec.rows - 1) * gap + inset * 2 + labelHeight)
    }

    // MARK: Geometry

    private func rect(column: Int, row: Int) -> CGRect {
        CGRect(x: inset + CGFloat(column) * (cell.width + gap),
               y: inset + CGFloat(row) * (cell.height + gap),
               width: cell.width, height: cell.height)
    }

    private func cellAt(_ point: CGPoint) -> (column: Int, row: Int)? {
        let column = Int((point.x - inset) / (cell.width + gap))
        let row = Int((point.y - inset) / (cell.height + gap))
        guard column >= 0, column < spec.columns, row >= 0, row < spec.rows else { return nil }
        return (column, row)
    }

    // MARK: Interaction

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = cellAt(point) else { return }
        isDragging = true
        selection = GridSelection(column: hit.column, row: hit.row)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, var current = selection else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = cellAt(point) else { return }
        current.focusColumn = hit.column
        current.focusRow = hit.row
        selection = current
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            isDragging = false
            selection = nil
            needsDisplay = true
        }
        guard let selection else { return }
        let zone = selection.zone(in: spec)

        // Dismiss the menu first so the window we are about to move is the one
        // the user was actually looking at, not the menu's own host.
        enclosingMenuItem?.menu?.cancelTracking()
        let handler = onSelect
        Task { @MainActor in
            handler?(zone)
        }
    }

    // A single click is a 1×1 selection, so mouseUp handles it too — no extra
    // path needed.

    override func mouseMoved(with event: NSEvent) {
        guard !isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let hit = cellAt(point) {
            selection = GridSelection(column: hit.column, row: hit.row)
        } else {
            selection = nil
        }
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self))
    }

    override func mouseExited(with event: NSEvent) {
        guard !isDragging else { return }
        selection = nil
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        for row in 0..<spec.rows {
            for column in 0..<spec.columns {
                let path = NSBezierPath(roundedRect: rect(column: column, row: row),
                                        xRadius: 3, yRadius: 3)
                if selection?.contains(column: column, row: row) == true {
                    NSColor.controlAccentColor.setFill()
                } else {
                    NSColor.secondaryLabelColor.withAlphaComponent(0.18).setFill()
                }
                path.fill()
            }
        }

        let text: String
        if let selection {
            let columns = selection.maxColumn - selection.minColumn + 1
            let rows = selection.maxRow - selection.minRow + 1
            text = "\(columns) × \(rows)"
        } else {
            text = "Drag to select"
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                              y: bounds.height - labelHeight - 1),
                  withAttributes: attributes)
    }
}
