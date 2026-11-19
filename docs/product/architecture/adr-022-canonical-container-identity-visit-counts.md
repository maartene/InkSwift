# ADR-022: One Canonical Path per Container for Visit Counts; Forward-Only Save Compatibility

**Status**: Accepted (maintainer, 2026-11-19 — option B1; forward-only save compatibility)
**Date**: 2026-11-19
**Deciders**: Maarten Engels (project owner), Morgan (solution architect)
**Feature**: reference-fidelity-backlog (issue #33)
**Amends**: ADR-016 (the "structural equality, two keys" note for visit counts); ADR-018 (rollback safety for `visitCounts` keys)

---

## Context

Visit counts are keyed by the path *spelling* the engine used to enter a container:

- Sequential entry appends a child index (`InkEngine.swift:92`).
- A divert uses the target's spelling (`:806`).

inklecate gives a named child of a content array both spellings, an index and a name, and the
decoder registers both (`InkDecoder.swift:172-177`). A labelled gather is therefore counted
under `0.0` on the first pass and under `0.loop` after `-> loop`. Every read count, and every
sequence's `visit` index, splits accordingly.

That is issue #33: multi-line sequences replay their first item once, and loops run one extra
pass. ADR-016's design recorded the two keys as intended
(`docs/feature/typed-runtime-paths/feature-delta.md:38-39`). Upstream `TestVisitCountsWhenChoosing`,
`TestVisitCountBugDueToNestedContainers` and `TestGatherReadCountWithInitialSequence` in the
conformance backlog show the same split.

**Reference.** C# counts per container. `Container.path` uses the child's name whenever it has
one (`Object.cs:86-89`). Counting happens in `VisitContainer` and
`VisitChangedContainersDueToDivert` (`Story.cs:975-1033`).

## Decision

1. **Canonical path.** `ContainerPathResolver` gains a query that maps any spelling of a
   container to its canonical path: a name for every named component, an index otherwise, as
   in C# `Object.path`. Memoising it is a crafter choice.
2. **One visit counter.** An engine-owned counter is the only writer and reader of
   `visitCounts`, and it keys by the canonical path. It serves:
   - `recordVisit` (sequential entry, absolute divert, choice continuation);
   - `.readCount`;
   - the `visit` control command. That command moves from `TreeWalker` into the engine,
     because it needs the resolver; `.readCount` already follows this pattern.
   - the host API `visitCount(forKnot:)` and `setVisitCount(forKnot:to:)`
     (`InkEngine.swift:1022-1031`), reached publicly through `Story.visitCount(forKnot:)`
     (`Facade/Story.swift:104-105`). A `knot` or `knot.stitch` name is already canonical,
     because knots and stitches are named content. Both still go through the counter, so
     there is one key policy.

   Frame and pointer paths keep their spelling (option B2 rejected below).

   **Lint scope.** The counter is a small engine type (for example `Engine/VisitCounter.swift`)
   wrapping `state.visitCounts`. The SwiftLint ban on `visitCounts[` excludes that file.
   `StoryState`'s hand-written `Codable` converts the dictionary as a whole and never
   subscripts it (`StoryState.swift:422-423, 447`), so it is unaffected. The `InkEngine`
   host-API methods delegate to the counter.
3. **Probe-gated scope.** Two further reference behaviours stay in DELIVER, decided by the F4
   conformance tests:
   - counting ancestors that a divert newly enters (`VisitChangedContainersDueToDivert`);
   - honouring count-at-start-only (`#f` flag value 4, mask `0x4`; C# `CountFlags.CountStartOnly = 4`, `Container.cs:73`).

   Each is adopted only if a conformance test or oracle fixture shows it is observable.
4. **Save compatibility: forward-only (amends ADR-018).**
   - `restoreState` converts every legacy `visitCounts` key to its canonical path, using the
     loaded story's tree. Counts that were split across two spellings are summed.
   - A save written by a new build is **not supported** on an older build: there a canonical
     key would be read under the other spelling and some counts would reset.
   - This replaces ADR-018's rollback-safety requirement for `visitCounts` keys only. All
     other fields keep ADR-018's byte-identical wire.

## Alternatives Considered

- **B2: canonicalise at entry** (`enterContainer` appends the name). **Rejected**: it changes
  the spelling of every saved `stackFrames` and `pointer` path, and the inputs to
  relative-divert anchoring. The save and behaviour blast radius is wider for the same fix.
- **B3: stamp each `ContainerNode` with its canonical path** after decode and after compile.
  This is clean identity, but `ContainerNode` would gain a field that both the decoder and the
  compiler must fill in a post-pass. **Rejected** for now; B1 can adopt it as a memoisation
  later without changing this decision.
- **Rollback-safe: write both spellings for one release.** **Rejected** by the maintainer:
  a permanent dual key, for a downgrade path users don't take.

## Consequences

**Positive**
- #33 is closed, and the three backlog tests are expected to pass (probe).
- Read counts no longer depend on how a container was reached.
- One choke point makes "visit count under the wrong key" non-representable. Enforcement:
  a SwiftLint `custom_rules` entry banning `visitCounts[` outside the visit counter.

**Negative (release-note callout)**
- Stories using multi-line sequences, labelled-gather loops or read counts of labelled
  gathers **play differently**: they now play correctly.
- **Saves from this release are not supported on older builds.** If one is restored on an
  older build anyway, visit counts recorded under a canonical spelling are read as 0 there.
  The story then replays sequence items and once-only content, and loops run extra passes.
- Older saves restore on the new build, with their split counts merged.
