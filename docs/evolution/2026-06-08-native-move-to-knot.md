# Evolution — native-move-to-knot

**Date**: 2026-06-08
**Feature ID**: native-move-to-knot
**Status**: COMPLETE
**Commit**: 45ac8f1
**Test result**: 179/179 GREEN

---

## Feature Summary

`native-move-to-knot` adds `public func moveToKnot(_ knot: String, stitch: String? = nil) throws` to the `Story` facade of `SwiftInkRuntime`. The method lets a developer redirect a running story to any named knot (or stitch) without reloading the story from JSON.

Before this feature, the only workaround was to reload the entire story from its JSON source and manually replay choices — slow and impossible to generalise for arbitrary jump targets. After this feature, `try story.moveToKnot("interrogation")` resets the engine state, positions the pointer at `interrogation`, and the next `story.continue()` returns the first line of that knot.

This is a brownfield extension: the `SwiftInkRuntime` engine already had full Tier 1–3 coverage (text, choices, variables, conditionals, functions, tunnels). The new feature adds one public method, one internal method, and one error case — touching two existing files only.

---

## Business Context

The primary persona is **Ava**, a Swift developer building a narrative game using `SwiftInkRuntime`. The three main use cases driving this feature:

- **Chapter-select**: let the player jump directly to any named scene from a table of contents.
- **Scene replay**: a "replay this chapter" button restarts from a known knot without reloading the whole story.
- **Developer debug jump**: skip to a specific scene without replaying the full story during development.

The feature brings `SwiftInkRuntime` to parity with:
- The JS-bridge layer (`InkStory.moveToKnitStitch`) already available in the same package.
- The C# reference runtime's `ChoosePathString(path, resetCallstack: true)`.

Developers who already use the JS-bridge API can adopt the native runtime's `moveToKnot` without changing application logic.

---

## New Public API

### Method signature

```swift
// Story.swift (public)
public func moveToKnot(_ knot: String, stitch: String? = nil) throws
```

### Error case

```swift
// StoryError enum (public)
case knotNotFound(String)
```

The associated value carries the attempted path string: the plain knot name for knot-only calls, or `"knot.stitch"` for compound calls. `StoryError` already derived `Equatable`, so the new case is automatically `Equatable`-conformant.

### Behaviour contract

- After a successful call, `canContinue` is `true` and the next `continue()` returns the first line of the target knot.
- The state fields cleared by the jump: `returnStack`, `evalStack`, `currentChoices`, `outputStream`, `callFrameVariables`, `suppressNextNewline`, `isEnded` (set `false`), `inTagMode`, `tagAccumulator`, `inStringMode`, `stringAccumulator`.
- The state fields preserved: `variablesState`, `visitCounts`, `chosenChoiceTargets`.
- The method does NOT auto-continue. The developer calls `continue()` explicitly after the jump.
- Path resolution happens before any state mutation. If the knot or stitch cannot be found, `knotNotFound` is thrown and the story state is unchanged.

---

## User Stories Covered

| Story | Title | Tests |
|---|---|---|
| US-01 | Jump to a Named Knot (happy path) | 10 tests |
| US-02 | Jump Throws knotNotFound for Non-Existent Knot | 5 tests |
| US-03 | Jump to a Knot + Stitch (compound path) | 5 tests |
| US-04 | Save/Restore Round-Trip After a Jump | 4 tests |

Total: 24 acceptance tests in `Tests/SwiftInkRuntimeTests/Acceptance/Milestone6_MoveToKnotTests.swift`.

---

## Key Architectural Decisions

### D1 — Reset strategy: direct field mutation

The 12 `StoryState` fields to clear are explicitly assigned in the body of `InkEngine.moveToKnot`. No helper method on `StoryState`, no full state reconstruction.

Rationale: Minimises code surface, keeps the reset co-located with the only call site, and avoids exposing mutable reset semantics to future callers. The reset list is explicit and auditable at code review. Two alternatives rejected:

- **Option B (`StoryState.reset(preserving:)` helper)**: conflates execution-semantic decisions with the pure data-container role of `StoryState`. One call site does not justify a new API plus a `StoryStatePreservation` type.
- **Option C (full `StoryState` reconstruction)**: the "implicit reset" advantage is illusory — future fields that must be preserved would be silently lost if not explicitly copied. Fails silently rather than loudly.

### D2 — Path resolution: direct `namedContent` lookup

Resolution uses `root.namedContent[knot]` (knot-only) and `root.namedContent[knot]?.namedContent[stitch]` (compound). The existing `navigateAbsolute(_:)` dotted-path walker is NOT used.

Rationale: Knot/stitch names are top-level named identifiers, not numeric path components. Using the dotted-path walker would conflate name-based navigation with index-based navigation and could produce false positives on numeric path components.

### D3 — Error contract: guard-then-throw (atomicity)

A single `guard` block resolves both knot and optional stitch before the first field mutation. If resolution fails, `knotNotFound` is thrown with no state touched.

Rationale: RD-02 mandates that no state mutation occurs before the throw. The single-guard pattern satisfies this atomically.

### D4 — Stack installation: delegate to `applyDivert`

After the state reset, `applyDivert(target: targetPath)` is called with the resolved dotted-path string. This replaces `containerStack` with a single new `ContainerFrame` and updates `state.pointer.containerPath`.

Rationale: `applyDivert` is the canonical stack-installation mechanism, exercised by all 154 pre-existing tests. Reusing it avoids duplicating stack-rebuilding logic and ensures correctness by construction.

### D5 — `stackFrames` not explicitly updated at jump time

`state.stackFrames` carries stale data between the jump and the next `saveState()` call. This is an existing engine invariant: the in-memory `containerStack` is authoritative during execution; `state.stackFrames` becomes authoritative only after `saveState()`. After the jump installs the new `containerStack`, the next `saveState()` call automatically captures the correct single-frame snapshot via `buildStackFrameSnapshot()`.

This means US-04 (save/restore after jump) required no special save/restore logic — the existing mechanism handled it correctly.

### D6 — Public API ownership

`Story` (facade) adds `public func moveToKnot(_:stitch:) throws`. `InkEngine` adds the corresponding internal method. Delegation follows the established one-liner pattern (e.g. `Story.chooseChoice` → `engine.chooseChoice`).

### D7 — `StoryError.knotNotFound(String)` as the first string-associated enum case

The existing `StoryError` enum already derived `Equatable`. Adding `case knotNotFound(String)` required no additional conformance code. The associated value carries the attempted path (plain knot name or compound `"knot.stitch"`), giving callers enough context to log the failure or surface a fallback.

---

## Implementation

### Scope

| Metric | Value |
|---|---|
| Steps | 1 (01-01: Implement InkEngine.moveToKnot guard-reset-install) |
| Commits | 1 (45ac8f1) |
| Files modified | 2 |
| New files | 0 |
| New StoryState fields | 0 |
| Pre-existing tests after feature | 154/154 GREEN |
| New acceptance tests | 24 (24/24 GREEN) |
| Total test suite | 179/179 GREEN |

### Files modified

- `Sources/SwiftInkRuntime/Engine/InkEngine.swift` — real implementation replacing the RED scaffold stub; guard-then-throw path resolution, 12-field state reset, `applyDivert` delegation.
- `Sources/SwiftInkRuntime/Facade/Story.swift` — SCAFFOLD comment removed; `knotNotFound(String)` case added to `StoryError`; public `moveToKnot` method delegates to engine.

### Test fixture

A new dedicated fixture was created for this feature:

- `Tests/SwiftInkRuntimeTests/slice-move-to-knot.ink` — Ink source
- `Tests/SwiftInkRuntimeTests/slice-move-to-knot.ink.json` — inklecate-compiled JSON (added to `Package.swift` resources)

The fixture contains six knots: `with_choices`, `score_setup`, `prologue`, `interrogation`, `epilogue`, `investigation` (with stitch `lab`).

### Execution log

| Step | Phase | Status | Timestamp |
|---|---|---|---|
| 01-01 | PREPARE | EXECUTED / PASS | 2026-06-08T08:31:05Z |
| 01-01 | RED_ACCEPTANCE | EXECUTED / PASS | 2026-06-08T08:31:15Z |
| 01-01 | RED_UNIT | SKIPPED / NOT_APPLICABLE | 2026-06-08T08:31:23Z |
| 01-01 | GREEN | EXECUTED / PASS | 2026-06-08T08:31:53Z |
| 01-01 | COMMIT | EXECUTED / PASS | 2026-06-08T08:32:17Z |

RED_UNIT was skipped: acceptance tests exercise the full public API port-to-port through the `Story` facade; no additional unit isolation was needed for a single-method implementation.

---

## DISTILL Wave Highlights

- **Walking skeleton strategy**: Strategy C (all adapters use real implementations; no fakes). The existing `WalkingSkeletonTests` remains the module WS — no new walking skeleton is needed for a brownfield addition.
- **Oracle comparison**: each jump scenario includes at least one oracle comparison test (macOS only) driving both `Story` (native) and `InkStory` (JS bridge) from the same fixture.
- **Oracle adjustment**: `InkStory.moveToKnitStitch` auto-continues internally; `Story.moveToKnot` does not. Oracle tests call `story.continue()` once on the native side after `moveToKnot` before comparing output.
- **Scaffold approach**: `StoryError.knotNotFound(String)`, the public `Story.moveToKnot` delegation stub, and the RED-throwing `InkEngine.moveToKnot` scaffold were installed first. Result: 24 RED tests, 0 BROKEN tests, 154 GREEN tests before any real implementation.

---

## Lessons Learned

1. **Scaffold-first approach works cleanly for single-method features.** Installing the `StoryError` case and the scaffold stubs before writing any real logic gave a clean RED baseline (24 RED, 0 BROKEN, 154 GREEN). The acceptance tests drove the exact implementation shape without ambiguity.

2. **Guard-then-throw prevents state corruption.** The single `guard` block collecting all resolution results before the first mutation is the right pattern for any operation that must be atomic in the face of partial resolution failure. The pattern is auditable at a glance: if the guard block succeeds, every subsequent line is guaranteed to have no path-resolution throw.

3. **`applyDivert` reuse validated by 154 pre-existing tests.** Rather than reimplementing stack installation, delegating to the existing `applyDivert` meant correctness was inherited from the existing test coverage. The 24 new acceptance tests then verified the complete jump lifecycle (reset + install + continue + save/restore).

4. **`stackFrames` invariant clarified.** The stale-`stackFrames` window between a jump and the next `saveState()` is an existing engine invariant, not one introduced by this feature. Documenting it explicitly in ADR-005 (Consequences — Negative) makes the invariant visible to future maintainers without requiring a code change.

5. **JS-bridge auto-continue deviation caught early.** The oracle adjustment (one extra `continue()` call on the native side) was identified in the DISCUSS wave and documented in RD-04. Having this documented before acceptance test authoring meant the oracle tests were written correctly the first time.

6. **Known gap accepted consciously.** The visit count update at jump time diverges from the C# runtime: `VisitChangedContainersDueToDivert()` is not called after the jump, so `READ_COUNT(knot)` on the very first line after a programmatic jump produces a count one lower than C# would produce. This gap is documented in ADR-005 (Consequences — Negative) with a developer workaround. None of the four user stories required the at-jump-time count update.

---

## Permanent Artifacts

| Artifact | Location | Type |
|---|---|---|
| ADR-005: moveToKnot Jump Strategy | `docs/product/architecture/adr-005-moveto-knot-jump-strategy.md` | Architectural decision record |
| Architecture brief section | `docs/product/architecture/brief.md` (§ native-move-to-knot) | Permanent subsection |
| Developer journey (YAML) | `docs/ux/native-move-to-knot/journey-developer.yaml` | UX artifact |
| Developer journey (visual) | `docs/ux/native-move-to-knot/journey-developer-visual.md` | UX artifact |
| Acceptance tests | `Tests/SwiftInkRuntimeTests/Acceptance/Milestone6_MoveToKnotTests.swift` | Test suite |
| Test fixture (Ink source) | `Tests/SwiftInkRuntimeTests/slice-move-to-knot.ink` | Test fixture |
| Test fixture (compiled JSON) | `Tests/SwiftInkRuntimeTests/slice-move-to-knot.ink.json` | Test fixture |

---

## References

- User stories: `docs/feature/native-move-to-knot/discuss/user-stories.md`
- DISCUSS wave decisions: `docs/feature/native-move-to-knot/discuss/wave-decisions.md`
- DESIGN wave decisions: `docs/feature/native-move-to-knot/design/wave-decisions.md`
- DISTILL wave decisions: `docs/feature/native-move-to-knot/distill/wave-decisions.md`
- ADR-005: `docs/product/architecture/adr-005-moveto-knot-jump-strategy.md`
- Architecture brief: `docs/product/architecture/brief.md`
