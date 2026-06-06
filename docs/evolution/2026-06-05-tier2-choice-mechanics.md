# Evolution: tier2-choice-mechanics

**Date**: 2026-06-05
**Branch**: native-runtime
**Feature ID**: tier2-choice-mechanics
**Status**: COMPLETE

---

## Feature Summary

Implemented Tier 2 Choice Mechanics for the `SwiftInkRuntime` pure-Swift Ink engine. This feature brings four slices of choice behaviour that are required before any realistic Ink story (including the Cass story and The Intercept) can run correctly:

- **Slice 01**: Once-only choice suppression (`flg & 0x10`) — picked `*` choices disappear on loop-back; `+` sticky choices remain.
- **Slice 02**: Conditional choice gating (`flg & 0x01`) — choices gated by `{condition}` blocks are absent when false, present when true.
- **Slice 03**: Visit count tracking and `CNT?` read counts — `{"CNT?": "knot"}` dict nodes push `visitCounts[key]` onto `evalStack`; containers with `#f` bit `0x1` increment their count on entry.
- **Slice 04**: Invisible default auto-divert — choices with `flags & 0x17 == 0` never appear in `currentChoices`; when no visible choices remain the engine auto-diverts to the first such target.

No new source files were introduced. All changes live in five existing files: `InkEngine.swift`, `StoryState.swift`, `TreeWalker.swift`, `NodeKind.swift`, and `InkDecoder.swift`.

---

## Business Context

The Cass story — the primary integration target for the `native-runtime` branch — was stuck re-showing once-only choices on every loop, making the story unplayable. Conditional gating, visit counts, and invisible defaults are similarly required by every non-trivial Ink story.

**Outcome KPIs — all met:**

| KPI | Baseline | Target | Result |
|-----|---------|--------|--------|
| KPI 1: Once-only suppression | 0% suppression | 100% | PASS — all Slice 01 tests green |
| KPI 2: Conditional choices gate correctly | 0% gated | 100% | PASS — all Slice 02 tests green |
| KPI 3: visitCounts correct after save/restore | CNT? always 0 | 100% correct | PASS — all Slice 03 tests green |
| KPI 4: No Tier 1 regressions | All green | 0 regressions | PASS — 95 total tests passing |

---

## Steps Completed

| Step ID | Name | COMMIT time |
|---------|------|-------------|
| 01-01 | Add chosenChoiceTargets and ChoiceData flags | 2026-06-05T10:20:34Z |
| 01-02 | Add NodeKind.readCount and InkDecoder CNT? handler | 2026-06-05T10:24:19Z |
| 02-01 | Once-only suppression in collection loop | 2026-06-05T10:28:37Z |
| 02-02 | Conditional gating in collection loop | 2026-06-05T10:31:17Z |
| 02-03 | Visit count increment and readCount dispatch | 2026-06-05T10:54:41Z |
| 02-04 | Invisible default auto-divert | 2026-06-05T11:02:03Z |

Total elapsed: ~44 minutes from first commit to final commit.

---

## Key Decisions

### D1 — Once-only suppression

The choice-collection loop in `InkEngine.stepToNextLine` skips a choice when `flags & 0x10 != 0` (once-only bit 4) AND `state.chosenChoiceTargets` contains its target path. `chooseChoice(at:)` records the target in `chosenChoiceTargets` for every once-only choice executed. `chosenChoiceTargets` is a `Set<String>` on `StoryState`, `Codable`, so suppression survives save/restore automatically.

### D2 — Conditional gating

When `flags & 0x01` is set, the engine pops the top of `state.evalStack` (the result of the preceding `ev … /ev` block). If the value is `false`, the choice is skipped. The pop is unconditional — even when skipping — to keep the stack balanced.

### D3 — CNT? is a dict node, not a native function

In inklecate-compiled JSON, visit count lookup is `{"CNT?": "knot_name"}` — a dict node — not a `"READ_COUNT"` native function string. The `InkDecoder.classifyDict` path previously fell through to `.controlCommand("CNT?")` which was silently ignored. Required changes:

1. `NodeKind.readCount(String)` case added.
2. `InkDecoder.classifyDict` matches `{"CNT?": key}` → `.readCount(key)`.
3. `TreeWalker.dispatch` handles `.readCount(key)` by pushing `state.visitCounts[key] ?? 0` as `.int`.
4. Container entry with `#f` bit `0x1` set increments `state.visitCounts[containerPath]`.

### D4 — Invisible default detection via combined predicate

inklecate v0.9 compiles `+ []` to `flg: 0` — the `isInvisibleDefault` spec bit (0x8) is NOT set. Detection uses all three conditions: `flags & 0x10 == 0` (not once-only) AND `flags & 0x06 == 0` (no text content) AND `flags & 0x01 == 0` (no condition), i.e. `flags & 0x17 == 0`. The first matching target is saved in a local `pendingInvisibleDefault`; post-collection, if `currentChoices` is empty and the variable is non-nil, the engine applies the divert and continues the step loop.

### D5 — StoryState.chosenChoiceTargets

New `Set<String>` field on `StoryState`, `Codable`, decoded via `decodeIfPresent` defaulting to `[]`. Encoded as sorted `Array` for deterministic output. Backward-compatible: existing saved states deserialise without error.

### D6 — ChoiceData.flags

New `flags: Int` field on `ChoiceData`, `Codable`, `decodeIfPresent` defaulting to `0`. Populated during choice collection from the in-flight choice node; read by `chooseChoice(at:)` to determine whether to record the target in `chosenChoiceTargets`.

---

## Issues Encountered (DISTILL upstream issues)

Three design issues were caught during the DISTILL wave acceptance-test creation and corrected before delivery:

### Issue 1 — Wrong once-only flag bit in brief

The brief stated once-only detection using `flags & 0x02`. The authoritative Ink JSON spec and inklecate output use bit 4 (`flags & 0x10`). Using `0x02` would suppress all bracketed choices. Corrected to `0x10` before any implementation.

### Issue 2 — Wrong invisible-default detection in brief

The brief stated `flags & 0x04`. inklecate v0.9 compiles `+ []` to `flg: 0` — no single bit is set. The combined predicate `flags & 0x17 == 0` was derived from observed fixture output and used in D4.

### Issue 3 — CNT? is not a READ_COUNT native function

The brief described a `handleNativeFunction` case for `"READ_COUNT"` that pops a path string from `evalStack`. Actual inklecate output uses a dict node `{"CNT?": "key"}` with the path embedded. Entire implementation strategy for D3 was revised accordingly (new `NodeKind` case + decoder handler + walker dispatch).

All three issues were caught by DISTILL before DELIVER. Zero regressions in Tier 1 tests after delivery.

---

## Lessons Learned

1. **Real compiler fixtures are non-negotiable.** All three design issues would have caused silent test failures if hand-crafted JSON had been used. inklecate-compiled fixtures immediately exposed the discrepancies between the spec document and actual compiler output.

2. **Flag bit arithmetic warrants its own test fixture column.** Documenting the exact `flg` integer value produced by inklecate for each choice type (not just the bit names) prevents future misinterpretation.

3. **DISTILL upstream-issues.md provides high leverage.** Catching all three issues before DELIVER started meant the roadmap steps were correct on the first attempt — every step went RED → GREEN → COMMIT with no rework.

4. **Combined-predicate invisible-default detection is robust.** Rather than relying on a single spec bit that the compiler may not honour, detecting invisible defaults by exclusion (`flags & 0x17 == 0`) is more resilient to compiler version differences.

5. **decodeIfPresent defaults make state evolution zero-friction.** Both `chosenChoiceTargets` and `ChoiceData.flags` used `decodeIfPresent` — existing save states round-trip without migration code.

---

## Migrated Permanent Artifacts

| Artifact | Permanent Location |
|----------|--------------------|
| Slice 01 acceptance specification | `docs/scenarios/tier2-choice-mechanics/slice-01-once-only-suppression.md` |
| Slice 02 acceptance specification | `docs/scenarios/tier2-choice-mechanics/slice-02-conditional-choice-gating.md` |
| Slice 03 acceptance specification | `docs/scenarios/tier2-choice-mechanics/slice-03-read-counts.md` |
| Slice 04 acceptance specification | `docs/scenarios/tier2-choice-mechanics/slice-04-invisible-defaults.md` |

Architecture documentation updated in place: `docs/product/architecture/brief.md` — Feature Coverage Matrix rows 8–11 and 14 updated to **IMPLEMENTED**.

---

## Discarded Artifacts

| File | Reason |
|------|--------|
| `deliver/execution-log.json` | Audit trail captured above |
| `deliver/roadmap.json` | Superseded by evolution doc + git history |
| `deliver/.develop-progress.json` | Resume state — temporary |
| `design/wave-decisions.md` | Key decisions extracted into this document |
| `discuss/wave-decisions.md` | Key decisions extracted into this document |
| `distill/wave-decisions.md` | Key decisions extracted into this document |
| `discuss/dor-validation.md` | Process gate |
| `discuss/story-map.md` | Superseded by roadmap execution |
| `discuss/user-stories.md` | Superseded by slice specs in `docs/scenarios/` |
| `distill/upstream-issues.md` | Issues captured in Lessons Learned above |
| `discuss/outcome-kpis.md` | KPI outcomes captured in Business Context above |
