# ADR-005: moveToKnot Jump Strategy — Reset and Stack Installation

**Status**: Accepted
**Date**: 2026-06-08
**Feature**: native-move-to-knot
**Decider**: Morgan (nw-solution-architect)

---

## Context

The `native-move-to-knot` feature adds `public func moveToKnot(_ knot: String, stitch: String? = nil) throws` to the `Story` facade. This API must:

1. Resolve a named knot (and optional stitch) from the story's compiled container tree.
2. Throw `StoryError.knotNotFound(attemptedPath)` before any state mutation if the path cannot be resolved.
3. Reset 12 specific `StoryState` fields (clearing execution callstack, evaluation stack, choices, output, and mode flags) while preserving `variablesState`, `visitCounts`, and `chosenChoiceTargets`.
4. Install a new `containerStack` pointing to the target knot/stitch container.
5. Not auto-continue — the caller drives execution explicitly via `continue()`.
6. Not add new `StoryState` fields (serialisation format unchanged).

The design question is: where does the reset logic live, how is the path resolved, and how is the stack installed?

---

## Decision

**Reset strategy**: Direct field mutation inside `InkEngine.moveToKnot`. The method explicitly assigns reset values to all 12 fields listed in RD-01 before calling `applyDivert`. No helper method on `StoryState`.

**Path resolution**: Direct `root.namedContent` dictionary lookups. Knot-only: `root.namedContent[knot]`. Compound: `root.namedContent[knot]?.namedContent[stitch]`. Does NOT use `navigateAbsolute(_:)` or the dotted-path walkers used by divert resolution.

**Stack installation**: Delegate to the existing `applyDivert(target:)` with the resolved dotted-path string. This replaces `containerStack` with a single new frame and updates `state.pointer.containerPath` — the canonical stack-installation mechanism.

**Error contract**: A single `guard` block resolves both knot and stitch before the first field mutation. If resolution fails, `knotNotFound` is thrown. No state is touched.

**`stackFrames` update**: Not explicitly updated during the jump. `state.stackFrames` is stale between the jump and the next `saveState()` call, which is an existing engine invariant (the in-memory `containerStack` is authoritative during execution; `state.stackFrames` becomes authoritative after `saveState()`).

---

## Alternatives Considered

### Alternative 1 — `StoryState.reset(preserving:)` helper

Add a mutating method to `StoryState` that encapsulates the reset logic. `InkEngine.moveToKnot` calls `state.reset(preserving: .globalState)`.

**Rejected because**: `StoryState` is a pure data container (`Codable` struct). Adding execution-semantic decisions (which fields to preserve across a jump) inside the state type conflates responsibilities. The single call site does not justify the additional API surface. A `StoryStatePreservation` type would be needed to parameterise preservation, adding complexity for no observable benefit.

### Alternative 2 — Full `StoryState` reconstruction

Construct a fresh `StoryState()` and copy `variablesState`, `visitCounts`, and `chosenChoiceTargets` from the current state.

**Rejected because**: The "implicit reset-by-construction" advantage is illusory — any future field that must be *preserved* is silently lost if not explicitly copied. Option A's explicit reset list fails loudly (forgotten reset is visible); Option C's omission-of-copy fails silently (forgotten preservation produces wrong behaviour). Additionally, `lastCompletedLine` and other fields require specific treatment that a naïve `StoryState()` swap does not handle.

---

## Consequences

### Positive

- Smallest code surface: +1 public method, +1 internal method, +1 enum case. Zero new files, zero new `StoryState` fields.
- Reuses `applyDivert` — the most-tested code path in the engine — for stack installation.
- Error contract is atomic: the `guard` block is the only place that can throw before mutation, which is trivially auditable.
- `buildStackFrameSnapshot()` at `saveState()` time automatically captures the post-jump single frame; US-04 (save/restore after jump) requires no special logic.
- No serialisation format change: existing saved states remain valid.

### Negative

- The reset field list in `InkEngine.moveToKnot` is a manual enumeration of 12 fields. A future `StoryState` field that should be reset on jump must be added to this list explicitly. A code comment in the method references RD-01 in `docs/feature/native-move-to-knot/discuss/wave-decisions.md` to make this obligation visible.
- `state.stackFrames` is stale between jump and `saveState()`. This is an existing engine invariant, not new to this feature, but it is now exercised by a new caller. The invariant should be documented in `InkEngine.saveState()` for future maintainers.
- **Known gap — visit count update at jump time**: The C# runtime calls `VisitChangedContainersDueToDivert()` immediately after `SetChosenPath`, which updates `visitCounts` for every container traversed by the jump. `SwiftInkRuntime` does not do this: visit counts for the target knot/stitch container are only incremented when execution actually enters that container during the first `continue()` call. This means that reading `READ_COUNT(knot)` or `TURNS_SINCE(knot)` inside the knot's own content on the very first line will produce a count that is one lower than the C# runtime would produce. **This gap is intentional** — adding an equivalent to `VisitChangedContainersDueToDivert()` would require a path-traversal pass over the container hierarchy at jump time, adding complexity that is not justified by the current feature scope (The Intercept does not exercise this pattern, and the four user stories do not require it). Developer workaround: if a story reads its own visit count on the first line after a programmatic jump, add one to the expected value, or restructure the Ink source to read the count after the first narrative beat rather than before it.

### Neutral

- `StoryError.knotNotFound(String)` is the first enum case with a String associated value. All other cases use `Int` or `String`. The existing `Equatable` derivation handles this automatically.

---

## References

- DISCUSS wave decisions: `docs/feature/native-move-to-knot/discuss/wave-decisions.md` (RD-01, RD-02, RD-03, RD-04)
- User stories: `docs/feature/native-move-to-knot/discuss/user-stories.md` (US-01 through US-04)
- DESIGN wave decisions: `docs/feature/native-move-to-knot/design/wave-decisions.md`
- C# reference: `ChoosePathString(path, resetCallstack: true)` in `ink-engine-runtime/Story.cs`
- Prior ADR: ADR-003 (state serialisation), ADR-004 (call/return mechanism — `returnStack` reuse)
