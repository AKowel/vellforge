import CoreGraphics
import Foundation

/// One window's place in a saved arrangement.
///
/// The frame is stored as a `Zone` — fractions of a display — rather than
/// pixels, so a layout captured on a 27-inch monitor restores sensibly onto a
/// laptop screen. The display is identified by UUID, not index, because indices
/// shuffle whenever monitors are reconnected in a different order.
public struct WindowSnapshot: Codable, Sendable, Equatable {
    public let bundleID: String
    public let title: String
    public let axIndex: Int
    public let displayID: String
    public let zone: Zone

    public init(bundleID: String, title: String, axIndex: Int,
                displayID: String, zone: Zone) {
        self.bundleID = bundleID
        self.title = title
        self.axIndex = axIndex
        self.displayID = displayID
        self.zone = zone
    }
}

public struct SavedLayout: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var windows: [WindowSnapshot]
    public var createdAt: Date

    public init(id: String, name: String, windows: [WindowSnapshot], createdAt: Date) {
        self.id = id
        self.name = name
        self.windows = windows
        self.createdAt = createdAt
    }

    /// Bundle identifiers referenced by this layout, for offering to relaunch
    /// whatever is not currently running.
    public var referencedApps: Set<String> {
        Set(windows.map(\.bundleID))
    }
}

/// A window currently on screen, reduced to what matching needs.
public struct MatchCandidate: Sendable, Equatable {
    public let bundleID: String
    public let title: String
    public let axIndex: Int

    public init(bundleID: String, title: String, axIndex: Int) {
        self.bundleID = bundleID
        self.title = title
        self.axIndex = axIndex
    }
}

/// Pairs saved windows with live ones.
///
/// This is the genuinely unsolved part of saved layouts: macOS provides no
/// window identifier that survives an application relaunch. Quit an app and
/// reopen it and its windows are, as far as the system is concerned, entirely
/// new objects. So matching is a *score*, not a lookup, and it will occasionally
/// be wrong for windows whose titles change — an unsaved document, a browser
/// tab. That is a limitation to state plainly, not a bug to chase.
public enum WindowMatcher {

    public static let defaultFloor = 20

    /// `nil` when the candidate is from a different application, which is an
    /// automatic disqualification rather than a low score.
    public static func score(_ snapshot: WindowSnapshot,
                             against candidate: MatchCandidate) -> Int? {
        guard snapshot.bundleID == candidate.bundleID else { return nil }

        // Being the same app is worth something on its own — a single-window
        // app whose title changed should still match.
        var score = 10

        if !snapshot.title.isEmpty, snapshot.title == candidate.title {
            score += 100
        } else if !snapshot.title.isEmpty, !candidate.title.isEmpty {
            if candidate.title.hasPrefix(snapshot.title)
                || snapshot.title.hasPrefix(candidate.title) {
                score += 50
            } else {
                let shared = commonPrefixCount(snapshot.title, candidate.title)
                if shared > 3 { score += min(30, shared) }
            }
        }

        if snapshot.axIndex == candidate.axIndex { score += 15 }
        return score
    }

    /// Greedy best-first assignment: every snapshot gets at most one live
    /// window and every live window is used at most once.
    ///
    /// Returns a map of snapshot index to candidate index. Snapshots with no
    /// acceptable match are simply absent — a layout should restore the windows
    /// it can find and leave the rest alone.
    public static func match(snapshots: [WindowSnapshot],
                             candidates: [MatchCandidate],
                             floor: Int = defaultFloor) -> [Int: Int] {
        var pairs: [(snapshot: Int, candidate: Int, score: Int)] = []
        for (si, snapshot) in snapshots.enumerated() {
            for (ci, candidate) in candidates.enumerated() {
                guard let value = score(snapshot, against: candidate), value >= floor
                else { continue }
                pairs.append((si, ci, value))
            }
        }

        // Deterministic ordering: score first, then indices, so the same inputs
        // always produce the same assignment.
        pairs.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.snapshot != $1.snapshot { return $0.snapshot < $1.snapshot }
            return $0.candidate < $1.candidate
        }

        var usedSnapshots = Set<Int>()
        var usedCandidates = Set<Int>()
        var result: [Int: Int] = [:]
        for pair in pairs {
            guard !usedSnapshots.contains(pair.snapshot),
                  !usedCandidates.contains(pair.candidate) else { continue }
            result[pair.snapshot] = pair.candidate
            usedSnapshots.insert(pair.snapshot)
            usedCandidates.insert(pair.candidate)
        }
        return result
    }

    private static func commonPrefixCount(_ a: String, _ b: String) -> Int {
        zip(a, b).prefix { $0 == $1 }.count
    }
}
