import CoreGraphics

public extension Display {
    /// Remap a window frame from this display onto `target`, preserving its
    /// relative position and proportions.
    ///
    /// A window filling the right half of a 27-inch monitor should still fill
    /// the right half after moving to a laptop screen — not keep its pixel size
    /// and hang off the edge, which is what naive translation produces.
    func remap(_ rect: CGRect, to target: Display) -> CGRect {
        let source = visibleFrame
        let dest = target.visibleFrame
        guard source.width > 0, source.height > 0 else { return rect }

        let fx = (rect.minX - source.minX) / source.width
        let fw = rect.width / source.width
        // Measure from the top so the result reads the same way `Zone` does.
        let fTop = (source.maxY - rect.maxY) / source.height
        let fh = rect.height / source.height

        let width = dest.width * fw
        let height = dest.height * fh
        return CGRect(x: dest.minX + dest.width * fx,
                      y: dest.maxY - dest.height * fTop - height,
                      width: width,
                      height: height)
    }
}

public extension Array where Element == Display {
    /// The display after `display`, wrapping around. Ordered left-to-right so
    /// "next display" matches the physical arrangement rather than whatever
    /// order the system happens to report.
    func next(after display: Display, reverse: Bool = false) -> Display? {
        guard count > 1 else { return nil }
        let ordered = sorted { $0.frame.minX < $1.frame.minX }
        guard let index = ordered.firstIndex(where: { $0.id == display.id }) else { return nil }
        let step = reverse ? -1 : 1
        let target = (index + step + ordered.count) % ordered.count
        return ordered[target]
    }
}
