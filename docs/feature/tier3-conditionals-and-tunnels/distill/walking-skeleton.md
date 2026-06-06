# Walking Skeleton Notes — tier3-conditionals-and-tunnels

**Wave**: DISTILL
**Updated**: 2026-06-06 (post-finalize addendum)
**Branch**: native-runtime

---

## Original walking skeleton (2026-06-05)

Not applicable — brownfield engine extension. The existing
`WalkingSkeletonTests` (from the `native-runtime` feature) remains the module's
walking skeleton. The Tier 3 feature ships six slice acceptance suites
(C1, C2, C3, T1, T2, T3) and a four-test The Intercept suite (smoke,
save/restore-15, full-oracle-choice-0, and the new non-trivial playthrough
added under DWD-07).

The `.feature` file in this project is the Swift Testing source file:
`Tests/SwiftInkRuntimeTests/Acceptance/Milestone5_Tier3ConditionalsAndTunnelsTests.swift`

---

## Addendum (2026-06-06) — non-trivial Intercept playthrough

Test file:
`Tests/SwiftInkRuntimeTests/Acceptance/Milestone5b_TheInterceptNonTrivialPlaythroughTests.swift`

Fixture (committed):
`Tests/SwiftInkRuntimeTests/TheIntercept_oracle_walkthrough.json`

### Design summary

The user requested a non-trivial partial playthrough of The Intercept,
comparing the first 50–100 lines to a JS-oracle reference. The
always-choose-0 ceiling-proof test (DWD-04) does not exercise the C3
function-call or T3 ref-param mechanisms because it loops on the opening
"Think" choice instead of advancing through Plan / Wait branches.

The new test commits a deterministic choice script
(`interceptChoiceScript = [0, 2, 1, 0, 0, 1, 2, 0, …]`, length 20). At every
choice point, the engine picks
`script[cursor % script.count] % currentChoices.count`. The modulo keeps the
script valid even if a future engine change alters choice counts at any
step.

The oracle reference is committed as
`TheIntercept_oracle_walkthrough.json` (100 lines captured from
`InkSwift.InkStory` driven by the same script). The acceptance test drives
the native `Story` through the same script and asserts each line equals the
fixture's `expectedLines[i]`.

### Driving port

`Story.init(json:)` (constructor) → `Story.continue()` /
`Story.chooseChoice(at:)` (drivers) → `Story.currentText` /
`Story.currentChoices` (observable outputs). Same driving port as every other
Tier 3 test — see DWD-04.

### Fixture regeneration

Manual. Set `REGEN_INTERCEPT_ORACLE=1`, run

```bash
REGEN_INTERCEPT_ORACLE=1 swift test --filter "regenerate The Intercept oracle walkthrough fixture"
```

The regen test writes the JSON to its source-adjacent path via `#filePath`.
Re-run `swift test` to pick up the regenerated fixture (SwiftPM copies it
into the test bundle as a resource).

### Current state

**RED** — exposes a real engine divergence (see `upstream-issues.md` Issue 5).
First 67 lines match line-for-line; line 67 is a spurious extra emission in
the native engine. Hand-off note in DWD-07.

### Self-review checklist

- [x] WS strategy declared (Strategy C — real local, inherited from DWD-01)
- [x] Scenarios tagged `@real-io`
- [x] Driving adapter exercised via the `Story` facade (not a back-door into `InkEngine`)
- [x] Real-IO `@adapter-integration` coverage — Bundle.module resource lookup
- [x] Test compiles GREEN — current failure is at assertion level, not import / scaffold level
- [x] Fixture committed and reproducible
- [x] Hard-coded sequence is shorter than the playthrough so it cycles
      deterministically; modulo against `currentChoices.count` keeps every
      choice valid
