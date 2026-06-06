# Outcome KPIs — tier2-choice-mechanics

## KPI 1 — Cass Story Plays Without Phantom Choices

**Target**: The Cass story (`cass.ink.json`) completes a full playthrough via InkTest with zero once-only choices reappearing after being picked.
**Measurement**: Manual InkTest playthrough of the full Cass story after Slice 01 ships. Automated: Milestone3 acceptance test that loops back to the gather point and asserts once-only choice is absent from `currentChoices`.
**Baseline**: Currently, every once-only choice reappears on every loop (0% suppression rate).
**Success threshold**: 100% of once-only choices suppressed after pick.

## KPI 2 — Conditional Choices Gate Correctly

**Target**: All `isConditional` choices in test fixtures evaluate correctly (absent when false, present when true).
**Measurement**: New acceptance tests in `Milestone2_StoryExecutionTests` covering false/true condition transitions.
**Baseline**: 0% of conditional choices are gated (they always appear regardless of condition).
**Success threshold**: 100% of `isConditional` choices respect their condition.

## KPI 3 — visitCounts Correct After Save/Restore

**Target**: `CNT?` returns the same value before and after a `saveState() → restoreState()` round-trip.
**Measurement**: Acceptance test: visit knot → save → restore → assert `CNT?` returns the same non-zero count.
**Baseline**: CNT? always returns 0 (function not wired).
**Success threshold**: `CNT?` returns correct counts in 100% of save/restore test cases.

## KPI 4 — No Regression in Tier 1 Acceptance Suite

**Target**: All existing Milestone1, Milestone2, Milestone3 acceptance tests continue to pass after each Tier 2 slice ships.
**Measurement**: `swift test` output; CI gate on `native-runtime` branch.
**Baseline**: Current suite: all green.
**Success threshold**: 0 regressions.
