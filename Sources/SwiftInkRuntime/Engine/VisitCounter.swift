/// The one reader and writer of `StoryState.visitCounts` (ADR-022 §2).
///
/// Every visit-count access in the engine goes through here: recording a visit
/// (sequential entry, absolute divert, choice continuation), the `.readCount`
/// lookup, the `visit` control command, and the host API
/// `visitCount(forKnot:)` / `setVisitCount(forKnot:to:)`. One place means one
/// key policy. A SwiftLint rule bans `visitCounts[` anywhere else in Sources/.
///
/// Keys are canonical container paths (ADR-022 §1): whichever spelling a caller
/// passes, index or name, one container has one count. A path that names no
/// container keeps its spelling.
///
/// Two C# counting rules are deliberately NOT adopted (ADR-022 §3, probe-gated,
/// step 01-05):
/// - Ancestor counting on divert (`VisitChangedContainersDueToDivert`,
///   Story.cs:1000-1033): its candidate evidence,
///   TestVisitCountBugDueToNestedContainers, passes on canonical keys alone, and
///   the oracle suite stays green without it.
/// - Count-at-start-only (`#f` bit 0x4, Container.cs:73): every place the engine
///   records a visit enters the container at its start, so the flag changes no
///   count here. TestVisitCountsWhenChoosing fails for another reason
///   (moveToKnot then a choice: invalidChoiceIndex), and TestKnotStitchGatherCounts
///   fails because a relative divert (`.^.^.^`, `.^.stitch`) records no visit,
///   which the flag alone cannot fix. Both stay in the conformance backlog.
struct VisitCounter {

    let resolver: ContainerPathResolver

    /// Bit 0 of a container's `#f` flags: the container tracks visit counts.
    private static let countVisitsFlag = 0x1

    /// Count a visit to `container`, stored under `path`, when it has the
    /// CountVisits flag. Mirrors C# `VisitContainer`.
    func recordVisit(to container: ContainerNode, at path: ContainerPath, in state: inout StoryState) {
        guard container.flags & Self.countVisitsFlag != 0 else { return }
        state.visitCounts[key(for: path), default: 0] += 1
    }

    /// The number of visits recorded under `path`; 0 when there are none.
    func count(at path: ContainerPath, in state: StoryState) -> Int {
        state.visitCounts[key(for: path)] ?? 0
    }

    /// Overwrite the count stored under `path`.
    func setCount(_ count: Int, at path: ContainerPath, in state: inout StoryState) {
        state.visitCounts[key(for: path)] = count
    }

    /// Re-key restored counts canonically (ADR-022 §4, forward-only saves).
    ///
    /// A save from before canonical keys may hold one container under both its
    /// index and its name spelling; those counts are summed under the canonical
    /// path. A key that names no container in the loaded story (content since
    /// removed or renamed) is kept as it is, not dropped, so a re-save
    /// preserves it.
    func canonicaliseKeys(in state: inout StoryState) {
        state.visitCounts = state.visitCounts.reduce(into: [:]) { merged, entry in
            merged[key(for: entry.key), default: 0] += entry.value
        }
    }

    private func key(for path: ContainerPath) -> ContainerPath {
        resolver.canonicalPath(of: path) ?? path
    }
}
