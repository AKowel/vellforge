import Testing
import CoreGraphics
@testable import SnapCore

@Suite("Grid selection")
struct GridTests {

    let spec = GridSpec(columns: 6, rows: 4)
    let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)

    @Test("a single top-left cell is the top-left fraction of the screen")
    func singleCell() {
        let zone = GridSelection(column: 0, row: 0).zone(in: spec)
        #expect(zone.resolve(in: screen) == CGRect(x: 0, y: 600, width: 200, height: 200))
    }

    @Test("row 0 is the top row, not the bottom")
    func rowZeroIsTop() {
        let top = GridSelection(column: 0, row: 0).zone(in: spec).resolve(in: screen)
        let bottom = GridSelection(column: 0, row: 3).zone(in: spec).resolve(in: screen)
        #expect(top.minY > bottom.minY)
        #expect(top.maxY == screen.maxY)
        #expect(bottom.minY == screen.minY)
    }

    @Test("selecting every cell fills the screen")
    func fullSelection() {
        let all = GridSelection(anchorColumn: 0, anchorRow: 0, focusColumn: 5, focusRow: 3)
        #expect(all.zone(in: spec).resolve(in: screen) == screen)
    }

    @Test("dragging backwards selects the same block as dragging forwards")
    func directionAgnostic() {
        let forwards = GridSelection(anchorColumn: 1, anchorRow: 1, focusColumn: 3, focusRow: 2)
        let backwards = GridSelection(anchorColumn: 3, anchorRow: 2, focusColumn: 1, focusRow: 1)
        #expect(forwards.zone(in: spec) == backwards.zone(in: spec))
    }

    @Test("containment covers the whole block regardless of drag direction")
    func containment() {
        let selection = GridSelection(anchorColumn: 4, anchorRow: 3, focusColumn: 2, focusRow: 1)
        #expect(selection.contains(column: 3, row: 2))
        #expect(selection.contains(column: 2, row: 1))
        #expect(selection.contains(column: 4, row: 3))
        #expect(!selection.contains(column: 1, row: 2))
        #expect(!selection.contains(column: 3, row: 0))
    }

    @Test("a left-half selection matches the left-half zone")
    func matchesNamedZone() {
        let spec = GridSpec(columns: 2, rows: 1)
        let left = GridSelection(column: 0, row: 0).zone(in: spec)
        #expect(left.resolve(in: screen) == Zone.leftHalf.resolve(in: screen))
    }
}

@Suite("Window matching")
struct WindowMatcherTests {

    func snapshot(_ bundle: String, _ title: String, index: Int = 0) -> WindowSnapshot {
        WindowSnapshot(bundleID: bundle, title: title, axIndex: index,
                       displayID: "d1", zone: .leftHalf)
    }

    func candidate(_ bundle: String, _ title: String, index: Int = 0) -> MatchCandidate {
        MatchCandidate(bundleID: bundle, title: title, axIndex: index)
    }

    @Test("a different app never matches, however similar the title")
    func differentAppNeverMatches() {
        #expect(WindowMatcher.score(snapshot("com.a", "Notes"),
                                    against: candidate("com.b", "Notes")) == nil)
    }

    @Test("an exact title beats a matching index")
    func exactTitleWins() {
        let snap = snapshot("com.a", "Report.md", index: 0)
        let byTitle = WindowMatcher.score(snap, against: candidate("com.a", "Report.md", index: 3))!
        let byIndex = WindowMatcher.score(snap, against: candidate("com.a", "Other.md", index: 0))!
        #expect(byTitle > byIndex)
    }

    @Test("a retitled single window still matches on index")
    func retitledStillMatches() {
        let snap = snapshot("com.a", "Untitled", index: 0)
        let score = WindowMatcher.score(snap, against: candidate("com.a", "Now Saved.txt", index: 0))
        #expect(score != nil)
        #expect(score! >= WindowMatcher.defaultFloor)
    }

    @Test("two windows of one app are assigned distinctly, never doubled up")
    func noDoubleAssignment() {
        let snapshots = [snapshot("com.a", "Left", index: 0),
                         snapshot("com.a", "Right", index: 1)]
        let candidates = [candidate("com.a", "Right", index: 0),
                          candidate("com.a", "Left", index: 1)]
        let result = WindowMatcher.match(snapshots: snapshots, candidates: candidates)
        #expect(result[0] == 1, "the window titled Left should win the Left snapshot")
        #expect(result[1] == 0)
        #expect(Set(result.values).count == result.count, "a candidate was used twice")
    }

    @Test("a snapshot with no live window is simply absent")
    func missingWindowsAreSkipped() {
        let snapshots = [snapshot("com.a", "Here"), snapshot("com.gone", "Missing")]
        let candidates = [candidate("com.a", "Here")]
        let result = WindowMatcher.match(snapshots: snapshots, candidates: candidates)
        #expect(result[0] == 0)
        #expect(result[1] == nil)
    }

    @Test("more live windows than saved ones leaves the extras alone")
    func extraWindowsUntouched() {
        let snapshots = [snapshot("com.a", "One", index: 0)]
        let candidates = [candidate("com.a", "One", index: 0),
                          candidate("com.a", "Two", index: 1),
                          candidate("com.a", "Three", index: 2)]
        let result = WindowMatcher.match(snapshots: snapshots, candidates: candidates)
        #expect(result.count == 1)
        #expect(result[0] == 0)
    }

    @Test("matching is deterministic when scores tie")
    func deterministicOnTies() {
        let snapshots = [snapshot("com.a", "", index: 0), snapshot("com.a", "", index: 0)]
        let candidates = [candidate("com.a", "", index: 0), candidate("com.a", "", index: 0)]
        let first = WindowMatcher.match(snapshots: snapshots, candidates: candidates)
        for _ in 0..<20 {
            #expect(WindowMatcher.match(snapshots: snapshots, candidates: candidates) == first)
        }
    }

    @Test("a document title that gained a prefix still matches")
    func prefixMatch() {
        let snap = snapshot("com.a", "Report")
        let score = WindowMatcher.score(snap, against: candidate("com.a", "Report — edited", index: 9))
        #expect(score != nil && score! > WindowMatcher.defaultFloor)
    }
}
