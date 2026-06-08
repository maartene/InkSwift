# DESIGN Decisions — native-move-to-knot

Date: 2026-06-08
Agent: Morgan (nw-solution-architect)
Mode: Propose

---

## Key Decisions

- [D1] Reset strategy: direct field mutation in `InkEngine.moveToKnot` (not a `StoryState.reset()` helper, not a full state reconstruction). Rationale: minimises surface area, keeps the reset co-located with the only call site, and avoids an API on `StoryState` that would expose mutable reset semantics to future callers who may misuse it. (see: `Engine/InkEngine.swift`, `Engine/StoryState.swift`)
- [D2] Path resolution: resolve via direct `root.namedContent` lookups (knot-only: `root.namedContent[knot]`; compound: `root.namedContent[knot]?.namedContent[stitch]`), NOT via the existing `applyDivert` / `navigateAbsolute` dotted-path walkers. Rationale: knot/stitch names are top-level named identifiers in the Ink content model; resolving through a dotted string path would conflate name-based navigation with index-based navigation and could match numeric path components incorrectly. (see: `Decoder/ContainerNode.swift`, `Engine/InkEngine.swift`)
- [D3] Error contract: `guard`-then-throw pattern — resolve path first, hold the `ContainerNode` reference, then throw before touching any `state` field if resolution fails. Rationale: RD-02 from DISCUSS wave mandates that no state mutation occurs before the throw; a single `guard` block collecting all resolution results and a single throw satisfies this atomically. (see: `Facade/Story.swift`, `Engine/InkEngine.swift`)
- [D4] `containerStack` installation: delegate to the existing `applyDivert(target:)` after state reset. `applyDivert` with an absolute dotted-path string already replaces `containerStack` with a single new frame and updates `state.pointer.containerPath`. This is the canonical stack-installation mechanism and reuses the exact same code path exercised by 154 passing tests. (see: `Engine/InkEngine.swift` — `applyDivert`)
- [D5] `stackFrames` in `StoryState` does NOT need explicit update during the jump. The in-memory `containerStack` is authoritative during execution; `state.stackFrames` is written only at `saveState()` time via `buildStackFrameSnapshot()`. After the jump installs the new `containerStack`, a subsequent `saveState()` call will automatically capture the correct single-frame snapshot. No special save/restore logic is required. (see: `Engine/InkEngine.swift` — `buildStackFrameSnapshot`, `saveState`)
- [D6] Public API ownership: `Story` (facade) adds `public func moveToKnot(_ knot: String, stitch: String? = nil) throws`; `InkEngine` adds `func moveToKnot(_ knot: String, stitch: String? = nil) throws` (internal). The facade's method delegates to the engine, matching the established one-liner delegation pattern (e.g. `Story.chooseChoice` → `engine.chooseChoice`). (see: `Facade/Story.swift`)
- [D7] `StoryError` gains `case knotNotFound(String)`. The associated value carries the attempted path string (knot-only, or compound `"knot.stitch"`). The existing enum already derives `Equatable`, so the new case is automatically `Equatable`-conformant without any additional code. (see: `Facade/Story.swift`)

---

## Architecture Summary

- Pattern: Brownfield extension — additive to existing ports-and-adapters (Facade → Engine) layered structure
- Paradigm: OOP with value-type state
- Key components: `Story` (facade, public), `InkEngine` (implementation, internal), `StoryError` (error taxonomy, public)
- No new source files; no new `StoryState` fields; no new runtime dependencies

---

## Options Considered

### Option A — Direct Field Mutation in `InkEngine.moveToKnot` (Recommended)

**Structure**: `InkEngine` gains a single `func moveToKnot(_ knot: String, stitch: String? = nil) throws` method. The method:
1. Resolves the target container via `root.namedContent` lookups (guard-then-throw before any mutation).
2. Directly assigns reset values to the twelve `state` fields listed in RD-01.
3. Calls `applyDivert(target:)` with the resolved dotted-path string to install `containerStack` and update `state.pointer`.

The reset block is explicit field assignments at the call site — readable, auditable, and co-located with the only caller.

**Trade-offs**:

| Attribute | Assessment |
|---|---|
| Maintainability | The reset list is visible at a glance in the single method body. Future field additions are detected at code review. |
| Testability | The method is directly testable via `@testable import`. Each AC maps to a direct assertion (field values post-call). |
| Correctness | Uses `applyDivert` — the same mechanism validated by 154 existing tests. |
| Save/restore invariant | No `StoryState` fields added; `buildStackFrameSnapshot` captures the new single-frame `containerStack` at `saveState()` time automatically. |
| Code surface | +1 internal method in `InkEngine`, +1 public method in `Story`, +1 enum case in `StoryError`. |

**Risk**: If a future feature adds a new `StoryState` field that also needs resetting on jump, the developer must remember to update `moveToKnot`. Mitigated by a comment listing the reset fields explicitly.

---

### Option B — `StoryState.reset(preserving:)` Helper Method

**Structure**: Add a mutating method `mutating func reset(preserving: StoryStatePreservation)` to `StoryState`. `InkEngine.moveToKnot` calls `state.reset(preserving: .globalState)` before installing the container stack.

**Trade-offs**:

| Attribute | Assessment |
|---|---|
| Maintainability | Reset logic is encapsulated in `StoryState`. Future new fields that should be reset are handled in one place. |
| Testability | `StoryState.reset` is independently unit-testable. However, testing the compound behaviour (reset + install) still requires engine-level tests. |
| Correctness | Introduces a new `StoryStatePreservation` type or set of parameters to express which fields to preserve — additional complexity for a single call site. |
| Save/restore invariant | No new `StoryState` fields; the method only mutates existing fields. |
| Code surface | +1 method on `StoryState`, +1 supporting type (`StoryStatePreservation`), +1 engine method, +1 facade method. More than Option A for the same behaviour. |
| Conway's Law | `StoryState` is a value type owned by the engine; adding a reset method makes it partially responsible for execution semantics — blurs the boundary between state storage and execution control. |

**Rejection reason**: Violates the principle of simplest solution first. `StoryState` is a pure data container (`Codable` struct); encoding execution-semantic decisions (which fields to preserve across a jump) inside the state type conflates responsibilities. Option A achieves the same correctness at lower complexity.

---

### Option C — Reconstruct `StoryState` from Scratch (Full Replacement)

**Structure**: `InkEngine.moveToKnot` constructs a fresh `StoryState()`, then copies `variablesState`, `visitCounts`, and `chosenChoiceTargets` from the current state into the new one. This is a "build then swap" approach.

**Trade-offs**:

| Attribute | Assessment |
|---|---|
| Maintainability | Implicit reset-by-construction: any new field defaults to its `init()` value, so forgetting to reset it is impossible. |
| Testability | Same as Option A. |
| Correctness | Risk: new fields added to `StoryState` that must be *preserved* (not just the three currently listed) will be silently lost. The preserve-list must be maintained, just on the copy side instead of the reset side. The failure mode is reversed but the maintenance burden is identical. |
| Save/restore invariant | Unchanged. |
| Code surface | Marginally more lines than Option A (three field copy-assignments). |

**Rejection reason**: The "implicit reset" advantage is illusory — any future field still requires a decision about preserve vs. reset, and Option C fails *silently* (lost preservation) rather than *loudly* (forgotten reset). Option A's explicit reset list is auditable at review time; Option C's omission-of-copy is not. Additionally, `lastCompletedLine` and `stackFrames` deserve their own treatment (the former should be cleared, the latter is rebuilt by `applyDivert` + `buildStackFrameSnapshot`), making a naive `StoryState()` swap still require post-construction patching.

---

## Recommended Option

**Option A — Direct Field Mutation in `InkEngine.moveToKnot`.**

Rationale:
- Smallest code surface consistent with all four user stories and all eight ACs.
- Reuses `applyDivert` — the most tested code path in the engine — for stack installation.
- No new `StoryState` fields (constraint 1 satisfied).
- No new source files (DISCUSS D3 satisfied).
- `buildStackFrameSnapshot` automatically captures the new frame at `saveState()` time (US-04 satisfied without special logic).
- Error contract (RD-02) is expressed by a single `guard` block before the first mutation.
- The reset field list is explicit and auditable: the 12 fields in RD-01 are assigned sequentially, with a comment referencing the DISCUSS decision document.

---

## Reuse Analysis

| Existing Component | File | Overlap | Decision | Justification |
|---|---|---|---|---|
| `Story` (facade) | `Facade/Story.swift` | Hosts all public API methods; delegation to engine | EXTEND | Add one public method following the established one-liner delegation pattern |
| `StoryError` | `Facade/Story.swift` | Error taxonomy for all throwing public methods | EXTEND | Add `case knotNotFound(String)`; enum already derives `Equatable` |
| `InkEngine` | `Engine/InkEngine.swift` | Owns `state: StoryState` and `containerStack`; contains `chooseChoice` which performs a similar reset-then-install pattern | EXTEND | Add one internal method; the reset pattern mirrors `chooseChoice` and the stack installation reuses `applyDivert` |
| `StoryState` | `Engine/StoryState.swift` | Holds all fields to be reset; `Codable` struct | NO CHANGE | All twelve reset fields already exist; no new fields, no new methods |
| `applyDivert(target:)` in `InkEngine` | `Engine/InkEngine.swift` | Resolves an absolute dotted-path string, replaces `containerStack` with a single new frame, updates `state.pointer.containerPath` | REUSE AS-IS | This is precisely the stack-installation mechanism needed after state reset; 154 tests validate it |
| `buildStackFrameSnapshot()` in `InkEngine` | `Engine/InkEngine.swift` | Snapshots `containerStack` into `state.stackFrames` at `saveState()` time | REUSE AS-IS | Automatically captures the post-jump single frame when `saveState()` is called; no change needed |
| `navigateAbsolute(_:)` in `InkEngine` | `Engine/InkEngine.swift` | Walks a dotted path from root; used by divert resolution, choice resolution, save/restore | NOT USED FOR JUMP | Knot/stitch resolution uses `root.namedContent` directly to avoid conflating name-based with index-based navigation |
| `framesFromSnapshots(_:)` in `InkEngine` | `Engine/InkEngine.swift` | Rebuilds `containerStack` from `ContainerStackFrame` array | NOT USED FOR JUMP | `applyDivert` is the correct installation path; `framesFromSnapshots` is for restore-time reconstruction |
| `ContainerNode.namedContent` | `Decoder/ContainerNode.swift` | Provides named sub-container lookup by string key | REUSE AS-IS | `root.namedContent[knot]` and `.namedContent[stitch]` are the direct resolution mechanism |

**No CREATE NEW decisions.** Every component decision is EXTEND or REUSE AS-IS.

---

## Component Interaction Sequence

```
Story.moveToKnot("knot", stitch: "stitch")
  → engine.moveToKnot("knot", stitch: "stitch")
      Step 1 — Path resolution (before any mutation):
        knotContainer = root.namedContent["knot"]       // nil → throw knotNotFound("knot")
        stitchContainer = knotContainer.namedContent["stitch"]  // nil → throw knotNotFound("knot.stitch")
        targetPath = stitch != nil ? "knot.stitch" : "knot"
      Step 2 — State reset (12 fields, RD-01):
        state.returnStack = []
        state.evalStack = []
        state.currentChoices = []
        state.outputStream = []
        state.callFrameVariables = []
        state.suppressNextNewline = false
        state.isEnded = false
        state.inTagMode = false
        state.tagAccumulator = ""
        state.inStringMode = false
        state.stringAccumulator = ""
        // state.stackFrames is NOT cleared here;
        // buildStackFrameSnapshot() at saveState() time will overwrite it.
      Step 3 — Stack installation:
        applyDivert(target: targetPath)
        // installs containerStack = [ContainerFrame(container: targetContainer,
        //   index: 0, pathFromRoot: [targetPath components])]
        // updates state.pointer.containerPath
      → returns (no throw, no auto-continue)
  → caller inspects canContinue (true), calls continue() explicitly
```

**Note on `stackFrames`**: The `state.stackFrames` field is left as-is during the jump. It carries stale data at that moment, but it is overwritten the next time `saveState()` is called (via `buildStackFrameSnapshot()`). If `restoreState()` were called without a preceding `saveState()` after the jump, it would restore from stale `stackFrames`. The design prevents this scenario: US-04 requires that `saveState()` is called after the jump before any restore.

**Invariant to document in code**: `stackFrames` in a live (non-saved) `StoryState` is not authoritative — `containerStack` is. `stackFrames` becomes authoritative only after `saveState()`. This is an existing invariant of the engine, not introduced by `moveToKnot`.

---

## Error Contract Detail

The attempted path string in `knotNotFound` is formed as follows:

| Call | Attempted Path |
|---|---|
| `moveToKnot("lab")` — knot not found | `"lab"` |
| `moveToKnot("")` | `""` |
| `moveToKnot("investigation", stitch: "dungeon")` — stitch not found | `"investigation.dungeon"` |

Path construction mirrors the JS-bridge: `stitch != nil ? "\(knot).\(stitch!)" : knot`.

---

## Technology Stack

- Swift 5.8+, Foundation: no new dependencies added
- No new Swift packages, no new runtime libraries
- Existing test infrastructure (Swift Testing + XCTest) unchanged

---

## Constraints Established

1. No new `StoryState` fields — serialisation format unchanged (DISCUSS constraint 1 honoured).
2. No new source files — all changes in three existing files: `Facade/Story.swift` (2 additions: public method + enum case), `Engine/InkEngine.swift` (1 addition: internal method).
3. `applyDivert` must remain the canonical stack-installation mechanism — `moveToKnot` must not reimplement stack rebuilding.
4. Path resolution must use `root.namedContent` direct lookup, not `navigateAbsolute` with a dotted string, to preserve the name/index navigation distinction.
5. No auto-continue — `moveToKnot` is a pure state-transition, not a step. RD-04.
6. The error throw must be the first observable effect of a failed call — no field touched before `guard` resolution succeeds.

---

## Upstream Changes

None. All DISCUSS wave assumptions are confirmed by codebase inspection:
- `applyDivert` exists and behaves as assumed.
- `root.namedContent` is a `[String: ContainerNode]` dictionary.
- `StoryError` already derives `Equatable`.
- `containerStack` is already replaced (not appended) by `applyDivert` for absolute paths.
- `buildStackFrameSnapshot` already runs at `saveState()` time, not at jump time.

One DISCUSS risk resolved: the JS-bridge `moveToKnitStitch` calls `continueStory()` internally. The native `moveToKnot` deliberately does not. Oracle comparison tests must call `continue()` once after `moveToKnot` on the native side, and treat the JS-bridge's internal `continueStory()` as producing the first line. This is noted in the DISCUSS risk table (Risk 3, probability: medium, impact: low). The acceptance-designer must account for this in oracle test scaffolding.
