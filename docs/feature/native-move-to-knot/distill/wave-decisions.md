# DISTILL Decisions — native-move-to-knot

**Wave**: DISTILL
**Designer**: nw-acceptance-designer
**Date**: 2026-06-08
**Branch**: main

---

## Prior Wave Reading Checklist

| Artifact | Status |
|---|---|
| `docs/feature/native-move-to-knot/discuss/journey-developer.yaml` | Read |
| `docs/product/architecture/brief.md` | Read |
| `docs/feature/native-move-to-knot/discuss/user-stories.md` | Read |
| `docs/feature/native-move-to-knot/discuss/story-map.md` | Read |
| `docs/feature/native-move-to-knot/discuss/wave-decisions.md` | Read |
| `docs/feature/native-move-to-knot/design/wave-decisions.md` | Read |
| `docs/product/architecture/adr-005-moveto-knot-jump-strategy.md` | Read |
| `docs/product/kpi-contracts.yaml` | Not found — soft gate, proceeding |
| `docs/feature/native-move-to-knot/spike/` | Not found — no spike ran, expected |
| `docs/feature/native-move-to-knot/devops/` | Not found — applying default environment matrix |

---

## Wave-Decision Reconciliation

**Result: 0 contradictions.**

All DISCUSS decisions (RD-01 through RD-04) are confirmed by DESIGN wave (D1–D7). No upstream changes.

One deviation documented (not a contradiction): DISCUSS RD-04 notes that JS-bridge `moveToKnitStitch` auto-continues internally while native `moveToKnot` does not. This is a deliberate API design choice, not a contradiction. Oracle comparison tests must call `story.continue()` once after `moveToKnot` to align with the oracle's auto-continued output.

---

## Key Decisions

### DWD-01 — Walking Skeleton Strategy: Strategy C (Real local)

**Decision**: Strategy C — all adapters use real implementations; no fakes or in-memory doubles.

**Rationale**: All resources are local filesystem adapters (inklecate-compiled JSON fixtures embedded in the test bundle). No costly external dependencies. Brownfield feature addition — the engine already boots and handles all Tier 1–3 mechanics. The story map explicitly states "No walking skeleton is designated because this is a brownfield feature addition." The existing `WalkingSkeletonTests` remains the module walking skeleton.

**Tagging**: All new scenarios use `@real-io @driving_adapter`. No `@in-memory` doubles.

---

### DWD-02 — Brownfield Feature — No New Walking Skeleton

**Decision**: No new walking skeleton scenario is added. The existing `WalkingSkeletonTests` (from the `native-runtime` feature) remains the module WS.

**Rationale**: The story map explicitly declares this brownfield — the engine already supports all prerequisite infrastructure (containerStack, returnStack, path resolution, save/restore). The DISTILL output is a full acceptance test suite covering US-01 through US-04.

---

### DWD-03 — Oracle Comparison Required for Jump Output

**Decision**: Each knot/stitch jump scenario includes at least one oracle comparison test (macOS only) that drives both `Story` (native) and `InkStory` (JS bridge) from the same inklecate-compiled fixture and asserts output equality.

**Oracle adjustment (per RD-04)**: `InkStory.moveToKnitStitch` auto-continues internally, producing the first line in `currentText`. `Story.moveToKnot` does NOT auto-continue. Oracle tests call `story.continue()` once on the native side after `moveToKnot`, then compare against `oracle.currentText` after `oracle.moveToKnitStitch`.

---

### DWD-04 — Save/Restore Invariant Required as Dedicated US-04 Suite

**Decision**: Save/restore scenarios are grouped as a dedicated US-04 suite (`US04_SaveRestoreAfterJumpTests`). Each save/restore test is independent of US-01 through US-03 happy-path tests to avoid cross-suite dependencies.

**Rationale**: US-04 is a separate user story in the story map with its own acceptance criteria. The save/restore invariant is a system-wide constraint (user-stories constraint 1) that requires explicit test coverage. The existing engine save/restore mechanism (`StoryState.Codable`) handles this without new logic — the tests verify that `applyDivert` + `buildStackFrameSnapshot` (called at `saveState()` time) correctly capture the post-jump single-frame state.

---

### DWD-05 — New Fixture: slice-move-to-knot.ink.json

**Decision**: A new dedicated fixture is created for native-move-to-knot tests:

| Source | Compiled JSON | Purpose |
|--------|--------------|---------|
| `slice-move-to-knot.ink` | `slice-move-to-knot.ink.json` | All moveToKnot acceptance tests |

**Knots in fixture**:
- `with_choices` — entry point; presents "You are at a crossroads." then 2 choices (creates dirty mid-execution state)
- `score_setup` — executes `~ score = 42` before jumping to epilogue (tests variable preservation)
- `prologue` — known first line: "Once upon a time there was a detective."
- `interrogation` — known first line: "Detective Mills enters the room."
- `epilogue` — outputs `{score}` (tests variable preservation via story output)
- `investigation` — knot with stitch `lab` (tests compound path navigation)

**Engine entry-point behavior note**: The fixture entry point is `with_choices`. After `Story.init(json:)`, two `continue()` calls are needed to reach the choice point — the first returns the text line, the second collects choice nodes. Tests that require choices to be present before the jump use `while story.canContinue { _ = story.continue() }` to exhaust content correctly.

---

### DWD-06 — Swift Scaffold Pattern for New Public API (Mandate 7)

**Decision**: The new public method `Story.moveToKnot(_:stitch:)` and the corresponding internal `InkEngine.moveToKnot(_:stitch:)` are scaffolded as RED stubs.

**Scaffold implementation**:
- `StoryError.knotNotFound(String)` added to `StoryError` enum in `Story.swift`
- `public func moveToKnot(_ knot: String, stitch: String? = nil) throws` added to `Story.swift` — delegates to engine
- `func moveToKnot(_ knot: String, stitch: String? = nil) throws` added to `InkEngine.swift` — throws `StoryError.invalidStateData` (placeholder that makes tests fail, not crash)
- Both methods marked `// SCAFFOLD: true`

**RED gate verification**:
- 154 existing tests: all GREEN (no regressions)
- 24 new tests: RED (scaffold throws `invalidStateData` before any assertion succeeds)
- 1 new test: GREEN (legitimately — `engine state is unchanged after a failed jump` tests that state is not mutated before the throw, which the scaffold satisfies correctly)
- 0 new tests: BROKEN (all compile, none crash)

**Test file**: `Tests/SwiftInkRuntimeTests/Acceptance/Milestone6_MoveToKnotTests.swift`

---

### DWD-07 — Package.swift Updated

**Decision**: `Package.swift` updated to:
- Add `"slice-move-to-knot.ink"` to the `exclude` list (`.ink` source, not processed as resource)
- Add `.process("slice-move-to-knot.ink.json")` to `SwiftInkRuntimeTests` resources

---

## Self-Review Checklist

- [x] 1. WS strategy declared (DWD-01: Strategy C)
- [x] 2. WS scenarios tagged `@real-io @driving_adapter`
- [x] 3. No driven adapters without real-io scenarios (only Bundle/Story adapters; all covered)
- [x] 4. No InMemory doubles — not applicable
- [x] 5. Container preference: no containers — real files on host
- [x] 6. **Mandate 7**: scaffold stubs created in `Story.swift` and `InkEngine.swift` with `// SCAFFOLD: true`
- [x] 7. **Mandate 7**: scaffold methods throw `StoryError.invalidStateData` (not a crash, not NotImplementedError)
- [x] 8. **Mandate 7**: Tests are RED (24) and not BROKEN (0) against scaffolds
- [x] 9. Driving adapter: `Story.init(json:)` is the driving port; all tests enter via it
- [x] 10. **F-001**: all scenarios exercise real fixtures from Bundle.module
- [x] 11. F-002–F-005: not applicable (Swift Testing, not pytest-bdd)
- [x] 12. Oracle tests account for RD-04 auto-continue deviation (native needs one extra `continue()`)
- [x] 13. Save/restore invariant tested as dedicated US-04 suite
