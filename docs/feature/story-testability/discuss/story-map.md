# Story Map: story-testability

## User: Raya — Swift developer and Ink story author
## Goal: Write automated Given-When-Then unit tests for Ink story logic without replaying the whole story

---

## Backbone

| Read State | Write State | Drain Output | Convenience |
|---|---|---|---|
| getVariable — read a VAR | setVariable — write a VAR | continueMaximally — drain all lines | (future: assertOutput helper) |
| visitCount — read a knot count | setVisitCount — write a knot count | | |

The backbone follows the GWT testing workflow left to right:
- **Read State** (verify preconditions / assert postconditions)
- **Write State** (inject GIVEN preconditions)
- **Drain Output** (execute the WHEN step)
- **Convenience** (ergonomic helpers — future)

---

## Story Map Table

```
ACTIVITY:  Read State       Write State        Drain Output       Convenience
           ─────────────    ─────────────────  ─────────────────  ─────────────
SLICE 01:  getVariable       —                  —                  —
           (read only)
           ─────────────────────────────────────────────────────────────────────
SLICE 02:  (getVariable)    setVariable         —                  —
                            (write + verify)
           ─────────────────────────────────────────────────────────────────────
SLICE 03:  visitCount       setVisitCount       —                  —
           (read only)      (write + verify)
           ─────────────────────────────────────────────────────────────────────
SLICE 04:  (all above)      (all above)        continueMaximally   —
                                               (full WHEN step)
```

Each row is a thin end-to-end slice. Each slice builds on the previous but ships independently.

---

## Walking Skeleton

**Note**: This is a brownfield additive feature — `Story` facade already exists, and `moveToKnot` provides the navigation primitive. The "walking skeleton" for this feature is the first slice that lets a story author write a GWT test with at least one new capability.

**Walking skeleton = Slice 01**: `getVariable` alone lets Raya write a THEN assertion after a full playthrough. While not the full GWT setup story, it delivers the first independently verifiable behavior — reading variable state without playing through to set it.

Minimum end-to-end behavior: `Story(json:) → moveToKnot → continue() → getVariable → #expect`

---

## Release Slices

### Slice 01: Read a VAR value (`getVariable`)
- **Outcome**: Story author can assert on variable state after `continue()` without raw StoryState access
- **Behavior**: `story.getVariable("score")` returns the current value of a VAR as `Int`, `Double`, `String`, `Bool`, or `nil`
- **Stories**: US-01
- **Effort**: 0.5 days
- **KPI target**: Variable post-condition assertions are possible in story unit tests

### Slice 02: Write a VAR value (`setVariable`)
- **Outcome**: Story author can inject GIVEN preconditions by setting variables directly — no choice-replay setup chain
- **Behavior**: `story.setVariable("score", to: 42)` writes a value into variablesState; unknown variable is a silent no-op
- **Stories**: US-02
- **Effort**: 0.5 days
- **KPI target**: Tests survive story refactoring that changes choice ordering

### Slice 03: Read and write knot visit counts (`visitCount` / `setVisitCount`)
- **Outcome**: Story author can test stories that use Ink's built-in `{knotName}` visit count syntax
- **Behavior**: `story.visitCount(forKnot: "prologue")` returns visit count; `story.setVisitCount(forKnot:to:)` injects it; unknown knot returns 0
- **Stories**: US-03
- **Effort**: 0.5 days
- **KPI target**: Visit-count-dependent story logic is unit-testable

### Slice 04: Drain all output (`continueMaximally`)
- **Outcome**: Story author executes the WHEN step in a single call, collecting all output to the next choice point — matches the inkjs/C# reference API
- **Behavior**: `story.continueMaximally()` loops `continue()` until `canContinue == false`, concatenates and returns all output lines
- **Stories**: US-04
- **Effort**: 0.5 days
- **KPI target**: Full GWT test is expressible in ~10 lines of Swift; manual while-loop is eliminated

---

## Priority Rationale

Slices are sequenced by outcome dependency and learning value:

| Priority | Slice | Rationale |
|---|---|---|
| 1 | Slice 01 — getVariable | Lowest-risk; read-only; validates the InkValue→Swift type bridging strategy before writing |
| 2 | Slice 02 — setVariable | Symmetric with get; depends on type bridging from Slice 01; highest user-value (GIVEN injection) |
| 3 | Slice 03 — visitCount / setVisitCount | Independent of variables; needed for Pattern B stories; low complexity, isolated state dict |
| 4 | Slice 04 — continueMaximally | Depends on nothing new (no state changes); completes the WHEN step; ergonomic improvement over manual loop |

Each slice ships independently and has value without the next slice. A story author can write partial GWT tests after each slice.

---

## Scope Assessment: PASS

4 user stories, 2 bounded contexts (Facade/Story.swift + Engine/StoryState.swift via InkEngine), estimated 2 days total (0.5 days per slice). Each slice is independently demonstrable and verifiable. No cross-cutting infrastructure changes required. Feature stays within the existing architecture (no new source files, no new StoryState Codable keys beyond what each slice needs).
