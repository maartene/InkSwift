# Definition of Ready Validation — tier2-choice-mechanics

| # | DoR Item | Status | Evidence |
|---|----------|--------|----------|
| 1 | User story has clear, testable acceptance criteria | ✅ PASS | Every story has numbered ACs with concrete observable outputs (`currentChoices` contents, text emitted). |
| 2 | Story is understood by the development team | ✅ PASS | All features derive from existing `brief.md` rows 8–11, 14. Code already partially implements parsing side; gaps are execution-side only. |
| 3 | Story has no blocking external dependencies | ✅ PASS | All features are internal to `SwiftInkRuntime`. No external API, no new SPM packages, no inklecate changes needed. |
| 4 | Story fits in one sprint / slice | ✅ PASS | Each slice is estimated ≤4 hours. Slice 01 (largest) requires two related behaviours (differentiation + suppression) but they share the same code path and are delivered together. |
| 5 | Non-functional requirements are specified | ✅ PASS | Save/restore invariant is an explicit cross-cutting AC on every story. Performance: tree-walker is synchronous; no async complexity introduced. |
| 6 | Story has a clear definition of done | ✅ PASS | Done = all ACs green in `swift test`, including the save/restore variant for each AC. |
| 7 | Dependencies between stories are identified | ✅ PASS | Story Map documents slice ordering. Slice 03 depends on Slice 01 (visitCounts reliability). Slice 04 depends on Slice 01 (once-only exhaustion to reach invisible-default state). |
| 8 | Acceptance tests can be written against the ACs | ✅ PASS | All ACs are expressed in terms of the public `Story` API (`currentChoices`, `continue()`, `saveState()`, `restoreState()`). Fixtures are inklecate-compiled `.ink.json` files following the project's established pattern. |
| 9 | Risks are identified | ✅ PASS | Key risks: (a) `flg` bit positions differ between Ink versions — mitigated by testing against inklecate-produced fixtures not hand-crafted JSON. (b) visitCounts path format may differ between named containers and choice containers — mitigated by using the same path key used in `buildStackFrameSnapshot`. |
