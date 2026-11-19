/// The one reader and writer of `StoryState.visitCounts` (ADR-022 §2).
///
/// Every visit-count access in the engine goes through here: recording a visit
/// (sequential entry, a divert, choice continuation), the `.readCount` lookup,
/// the `visit` control command, and the host API `visitCount(forKnot:)` /
/// `setVisitCount(forKnot:to:)`. One place means one key policy. A SwiftLint
/// rule bans `visitCounts[` anywhere else in Sources/.
///
/// Keys are canonical container paths (ADR-022 §1): whichever spelling a caller
/// passes, index or name, one container has one count. A path that names no
/// container keeps its spelling.
///
/// Divert counting follows C# (ADR-022 §3; adopted in step 01-07, reversing
/// 01-05's "not adopted"). `recordDivert` is Story.cs
/// `VisitChangedContainersDueToDivert` (~987-1035): walk up from the divert's
/// landing point and count each container until reaching one the flow was
/// already inside. Evidence it is observable: upstream TestKnotStitchGatherCounts
/// failed on main, because a relative divert (`-> .^.stitch`, a gather loop's
/// `.^.^.^`) counted nothing, and `divert-visit-counts.ink` shows inklecate
/// also counting a knot when a divert lands on one of its stitches. Absolute,
/// relative, tunnel and function-call diverts all walk; a variable divert does
/// not (C# `PointerAtPath` points it at the container itself, index -1, and the
/// walk returns early), so only its target is counted, as C# `Step` does.
/// Choice continuations keep their single record: the walk from a choice body
/// stops at its parent, which holds the choice point.
///
/// Count-start-only (`#f` bit 0x4, Container.cs:73; set on gathers, choice
/// bodies and sequences) is honoured, because the walk depends on it: such a
/// container is walked even when the flow was already inside it, and counted
/// only when entered at its first leaf. Both halves are observable: a labelled
/// gather's `.^.^.^` loop counts each pass (TestKnotStitchGatherCounts, "2 2"),
/// and the conditional's rejoin `.^.^.^.22` back into that same gather, mid-way,
/// does not ("After the rounds, round 3" in divert-visit-counts.ink). A knot
/// lacks the flag, so `-> knot` from inside itself does not count it ("Loop knot
/// 1", three times, as inklecate prints). That is matched deliberately
/// (maintainer decision): upstream TestKnotStitchGatherCounts expects it,
/// inkle/ink #164 (closed 2016) calls it intended, and #297, asking otherwise,
/// has had no maintainer reply since 2017. InkSwift used to count it.
///
/// Ancestor counting was not needed for TestVisitCountBugDueToNestedContainers
/// (01-05: canonical keys alone fixed it); it is adopted now for the cases above.
struct VisitCounter {

    let resolver: ContainerPathResolver

    /// Bit 0 of a container's `#f` flags: the container tracks visit counts.
    private static let countVisitsFlag = 0x1

    /// Bit 2 of a container's `#f` flags: count only entries at its start.
    private static let countStartOnlyFlag = 0x4

    /// Count a visit to `container`, stored under `path`, when it has the
    /// CountVisits flag. Mirrors C# `VisitContainer`.
    func recordVisit(to container: ContainerNode, at path: ContainerPath, in state: inout StoryState) {
        guard container.flags & Self.countVisitsFlag != 0 else { return }
        state.visitCounts[key(for: path), default: 0] += 1
    }

    /// Count the containers a divert entered, landing at child `index` of the
    /// container at `landing`, coming from inside `previous` (nil: from nowhere,
    /// as after C# `ResetCallstack`). Mirrors C# `VisitChangedContainersDueToDivert`.
    func recordDivert(
        from previous: ContainerPath?,
        landingAt index: Int,
        in landing: ContainerPath,
        state: inout StoryState
    ) {
        let alreadyInside = previous.map(resolver.lineage(of:)) ?? []
        var enteredAtStart = true
        for enclosure in resolver.enclosures(ofChild: index, in: landing) {
            let countsStartOnly = enclosure.container.flags & Self.countStartOnlyFlag != 0
            guard alreadyInside.contains(enclosure.path) == false || countsStartOnly else { return }
            enteredAtStart = enteredAtStart && enclosure.entersAtFirstChild
            if enteredAtStart || countsStartOnly == false {
                recordVisit(to: enclosure.container, at: enclosure.path, in: &state)
            }
        }
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
