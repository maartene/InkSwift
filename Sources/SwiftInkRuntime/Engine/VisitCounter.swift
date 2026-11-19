/// The one reader and writer of `StoryState.visitCounts` (ADR-022 §2).
///
/// Every visit-count access in the engine goes through here: recording a visit
/// (sequential entry, absolute divert, choice continuation), the `.readCount`
/// lookup, the `visit` control command, and the host API
/// `visitCount(forKnot:)` / `setVisitCount(forKnot:to:)`. One place means one
/// key policy. A SwiftLint rule bans `visitCounts[` anywhere else in Sources/.
///
/// Keys are the paths the callers pass, unchanged.
struct VisitCounter {

    /// Bit 0 of a container's `#f` flags: the container tracks visit counts.
    private static let countVisitsFlag = 0x1

    /// Count a visit to `container`, stored under `path`, when it has the
    /// CountVisits flag. Mirrors C# `VisitContainer`.
    func recordVisit(to container: ContainerNode, at path: ContainerPath, in state: inout StoryState) {
        guard container.flags & Self.countVisitsFlag != 0 else { return }
        state.visitCounts[path, default: 0] += 1
    }

    /// The number of visits recorded under `path`; 0 when there are none.
    func count(at path: ContainerPath, in state: StoryState) -> Int {
        state.visitCounts[path] ?? 0
    }

    /// Overwrite the count stored under `path`.
    func setCount(_ count: Int, at path: ContainerPath, in state: inout StoryState) {
        state.visitCounts[path] = count
    }
}
