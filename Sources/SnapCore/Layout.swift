import CoreGraphics

/// A named arrangement of a whole screen into cells.
///
/// Layouts exist because plenty of useful arrangements cannot be expressed as a
/// single screen edge — "two thirds plus a third", or a half beside two stacked
/// quarters, have no edge to drag to.
public struct Layout: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let cells: [Zone]

    public init(id: String, name: String, cells: [Zone]) {
        self.id = id
        self.name = name
        self.cells = cells
    }
}

public extension Layout {
    /// The whole screen, as the first tile, so the chooser covers "just make
    /// it big" as well as the splits.
    static let fullScreen = Layout(id: "fullScreen", name: "Full Screen",
                                   cells: [.full])

    static let halves = Layout(id: "halves", name: "Halves",
                               cells: [.leftHalf, .rightHalf])

    static let thirds = Layout(id: "thirds", name: "Thirds",
                               cells: [.leftThird, .centerThird, .rightThird])

    static let wideLeft = Layout(id: "wideLeft", name: "Wide Left",
                                 cells: [.leftTwoThirds, .rightThird])

    static let wideRight = Layout(id: "wideRight", name: "Wide Right",
                                  cells: [.leftThird, .rightTwoThirds])

    static let quarters = Layout(id: "quarters", name: "Quarters",
                                 cells: [.topLeft, .topRight, .bottomLeft, .bottomRight])

    /// A main pane on the left with a stacked sidebar — the arrangement most
    /// people actually build by hand.
    static let mainAndStack = Layout(
        id: "mainAndStack", name: "Main + Stack",
        cells: [
            .leftHalf,
            Zone(x: 0.5, y: 0,   width: 0.5, height: 0.5),
            Zone(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ])

    static let presets: [Layout] = [
        .fullScreen, .halves, .thirds, .wideLeft, .wideRight, .quarters, .mainAndStack,
    ]
}
