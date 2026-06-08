# DISCUSS Wave Decisions — native-move-to-knot

Date: 2026-06-08
Agent: Luna (nw-product-owner)

---

## Decisions Applied (from feature request)

| Decision | Value | Rationale |
|---|---|---|
| D1 — Platform | Backend (library API) | SwiftInkRuntime is a Swift library; no UI, no TUI |
| D2 — Walking skeleton | Skipped | Brownfield — native runtime already exists with full Tier 1–3 coverage |
| D3 — Scope | Lightweight | Focused API addition; no new source files expected |
| D4 — JTBD | Skipped | Proceed directly to journey design per feature request |

---

## Scope Assessment

PASS — 4 stories, 1 bounded context (SwiftInkRuntime), estimated 2 days effort.

No story touches more than `Story.swift`, `InkEngine.swift`, and the `StoryError` enum. No new source files required.

---

## Prior DIVERGE Artifacts

No DIVERGE wave was run for this feature. No `recommendation.md` or `job-analysis.md` found in `docs/feature/native-move-to-knot/diverge/`. Noted as acceptable per feature request instructions (D4: no JTBD).

---

## Key Requirements Decisions

### RD-01: State fields to reset vs. preserve

**Decision**: On a successful jump, clear: `returnStack`, `evalStack`, `currentChoices`, `outputStream`, `callFrameVariables`, `suppressNextNewline`, `isEnded` (set false), `inTagMode`, `tagAccumulator`, `inStringMode`, `stringAccumulator`, `stackFrames` (replace with single target frame).

Preserve: `variablesState`, `visitCounts`, `chosenChoiceTargets`.

**Rationale**: Mirrors C# `ChoosePathString(path, resetCallstack: true)`. Variables and visit counts accumulate across the session and are intentionally shared across jumps.

### RD-02: Error is thrown before any state mutation

**Decision**: Path resolution happens first. If the path cannot be resolved, throw `StoryError.knotNotFound(attemptedPath)` before touching any state field.

**Rationale**: Ensures the story is in a defined state after a failed jump. Developers can safely catch the error and continue on the original story flow.

### RD-03: Method signature mirrors JS-bridge

**Decision**: `public func moveToKnot(_ knot: String, stitch: String? = nil) throws`

**Rationale**: Matches the existing `InkStory.moveToKnitStitch(_:stitch:)` contract (parameter names adjusted for clarity; `throws` added since the JS bridge uses silent failure). Oracle parity requires the same knot/stitch naming convention.

### RD-04: Story does NOT auto-continue after jump

**Decision**: `moveToKnot` does NOT call `continue()` internally. The developer calls `continue()` explicitly after the jump.

**Rationale**: The JS-bridge `moveToKnitStitch` calls `continueStory()` internally, but the native runtime follows the explicit-continue contract established by the existing `Story.continue()` API (see ADR-002). Auto-continuing would break the developer's ability to inspect `canContinue` before continuing, and would conflict with the single-responsibility principle of the facade. This is a deliberate deviation from the JS-bridge behaviour.

---

## Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Path resolution does not match inklecate's namedContent hierarchy for stitches | Low | High | Verify against inklecate-compiled fixture before implementing; oracle comparison test catches mismatches |
| Stale field in state reset causes incorrect first continue() | Medium | High | AC explicitly lists all 12 reset fields; test with a dirty state (active tunnels + choices + ended) before jump |
| InkStory.moveToKnitStitch auto-continues; Story.moveToKnot does not — oracle test requires adjustment | Medium | Low | Oracle comparison test must account for one extra continue() call in the JS-bridge flow |

---

## Handoff to DESIGN Wave

The following artifacts are ready for solution-architect (DESIGN wave):

- `docs/feature/native-move-to-knot/discuss/journey-developer-visual.md`
- `docs/feature/native-move-to-knot/discuss/journey-developer.yaml`
- `docs/feature/native-move-to-knot/discuss/story-map.md`
- `docs/feature/native-move-to-knot/discuss/shared-artifacts-registry.md`
- `docs/feature/native-move-to-knot/discuss/user-stories.md`
- `docs/feature/native-move-to-knot/discuss/outcome-kpis.md`
- `docs/feature/native-move-to-knot/discuss/dor-validation.md` (all 4 stories PASSED)

DoR gate: PASSED (4/4 stories).
Peer review: APPROVED (0 critical, 0 high issues).
