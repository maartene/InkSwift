# DELIVER Upstream Issues — tier3-conditionals-and-tunnels

**Wave**: DELIVER
**Date**: 2026-06-06
**Source**: Acceptance-test gate verification at orchestrator pickup

These issues were discovered when the orchestrator picked up the DELIVER wave to run the
The-Intercept ceiling proof (DWD-04). Although `execution-log.json` records all six steps
01-01…01-06 as COMMIT/PASS, running the actual test suite reveals 41 of 148 tests are red,
including four of the six slice acceptance suites. The crafter did not enforce the
"acceptance test gate after each step's COMMIT/PASS" rule from the DELIVER skill.

---

## Issue 1 — `state.isEnded` leaks from `global decl` initialisation

**Severity**: BLOCKER — single root cause for all C1/C2/C3/T3 slice failures and the
Intercept smoke test failure
**Source file**: `Sources/SwiftInkRuntime/Engine/InkEngine.swift`
**Discovered in**: TheIntercept playthrough; reproduced in slice fixtures
**Affects DESIGN doc**: None (this is an implementation oversight)

**Finding**: `InkEngine.initializeGlobalVariables()` walks the `global decl` named container
flat with `walker.dispatchNode` for each child. Real inklecate-compiled stories end
`global decl` with the `"end"` control command (followed by `null`). `TreeWalker.handleControlCommand`
treats `"end"` (and `"done"`) by setting `state.isEnded = true`, which then prevents the
real story from ever advancing — `canContinue` short-circuits to `false`.

**Evidence**: `Tests/SwiftInkRuntimeTests/TheIntercept.ink.json` `global decl` ends with
`[..., '/ev', 'end', null]`. After `Story.init(json:)` the engine's `canContinue` is
already `false`. Slice fixtures C1/C2/C3/T3 each have the same pattern; T1/T2 do not
declare any globals so their `global decl` is absent.

**Implication for crafter**:
1. After `initializeGlobalVariables()` finishes processing the decl children, reset
   `state.isEnded = false` (and `state.pointer.index = 0` if it has been bumped to
   `Int.max` by the "end" handler).
2. Add a regression test that constructs `InkEngine` from a fixture whose `global decl`
   ends with `"end"` and asserts `canContinue == true` directly after init.
3. Verify all six existing slice acceptance suites pass after the fix.

---

## Issue 2 — Acceptance-test gate not enforced after slice commits

**Severity**: PROCESS — the execution log records PASS for steps whose acceptance suites
were never actually run green
**Source**: DELIVER skill step 3.i: "Acceptance test gate: after each step's COMMIT/PASS,
run `tests/acceptance/{feature-id}/`. Fix failures before proceeding to next step. No
deferral."
**Discovered in**: `docs/feature/tier3-conditionals-and-tunnels/deliver/execution-log.json`

**Finding**: All six commits show `COMMIT/PASS`, but `swift test --filter "Slice_C1"`
fails 7/7 with `.invalidChoiceIndex` errors (downstream of Issue 1). The crafter
recorded PASS without running the slice acceptance suite.

**Implication for orchestrator**: This is documented here for traceability. After the
Issue-1 fix lands, the orchestrator re-runs the full slice suite and confirms green
before proceeding to refactor.

---

## Issue 3 — Intercept full oracle playthrough deferred to a separate feature

**Severity**: SCOPE — the DWD-04 #3 test ("full playthrough matches JS oracle") is
unlikely to be GREEN purely from the Issue-1 fix; many additional engine differences
will surface once `canContinue` returns true.
**Discovered**: by inspection at handover

**Decision per user (2026-06-06)**: Scope DELIVER completion for this feature to:
- Smoke + 15-step save/restore invariant test green (DWD-04 #1 and #2)
- All six slice acceptance suites green

A meaningful-playthrough proof (first 50–100 lines of `The Intercept` matching the JS
oracle on a deterministic non-trivial choice path) and the full 2000-step ceiling proof
are explicitly **out of scope** for `tier3-conditionals-and-tunnels`. They will be
handled in a separate, follow-on feature so that this delivery can close and refactor
can proceed.
