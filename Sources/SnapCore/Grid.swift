import CoreGraphics

/// The grid exposed by the menu bar picker.
public struct GridSpec: Sendable, Equatable, Codable {
    public var columns: Int
    public var rows: Int

    public init(columns: Int = 6, rows: Int = 4) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }
}

/// A rectangular block of grid cells, given by any two corners.
///
/// Stored unnormalised so the view can hand over "where the drag started" and
/// "where it is now" without caring which direction it went.
public struct GridSelection: Equatable, Sendable {
    public var anchorColumn: Int
    public var anchorRow: Int
    public var focusColumn: Int
    public var focusRow: Int

    public init(anchorColumn: Int, anchorRow: Int, focusColumn: Int, focusRow: Int) {
        self.anchorColumn = anchorColumn
        self.anchorRow = anchorRow
        self.focusColumn = focusColumn
        self.focusRow = focusRow
    }

    public init(column: Int, row: Int) {
        self.init(anchorColumn: column, anchorRow: row, focusColumn: column, focusRow: row)
    }

    public var minColumn: Int { min(anchorColumn, focusColumn) }
    public var maxColumn: Int { max(anchorColumn, focusColumn) }
    public var minRow: Int { min(anchorRow, focusRow) }
    public var maxRow: Int { max(anchorRow, focusRow) }

    public func contains(column: Int, row: Int) -> Bool {
        column >= minColumn && column <= maxColumn && row >= minRow && row <= maxRow
    }

    /// Row 0 is the top row, matching `Zone`'s top-left origin.
    public func zone(in spec: GridSpec) -> Zone {
        let columns = Double(spec.columns)
        let rows = Double(spec.rows)
        return Zone(x: Double(minColumn) / columns,
                    y: Double(minRow) / rows,
                    width: Double(maxColumn - minColumn + 1) / columns,
                    height: Double(maxRow - minRow + 1) / rows)
    }
}
