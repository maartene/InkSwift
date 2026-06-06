# Evolution: tier3-conditionals-and-tunnels

**Date**: 2026-06-06
**Branch**: native-runtime
**Feature ID**: tier3-conditionals-and-tunnels
**Status**: COMPLETE

---

## Feature Summary

Implemented Tier 3 of the `SwiftInkRuntime` pure-Swift Ink engine: conditional text,
Ink functions, tunnels, and reference parameters. With this tier landed,
`SwiftInkRuntime` can play **The Intercept** (inkle, MIT) end-to-end against the
JavaScript-bridge oracle — the upper bound the project's coverage matrix
(`docs/product/architecture/brief.md`) targets for this milestone.

Slices delivered:

- **C1 — Inline Conditional Text** (`{condition: a|b}`) — reuses the existing
  `isConditional` divert pathway; no new NodeKind cases.
- **C2 — Block and Switch Conditionals** — shares the C1 mechanism. Switch
  dispatch uses the existing `==` native function plus per-case conditional
  diverts.
- **C3 — Ink Functions** — `{"f()": path}` decoded as a function-call divert
  (tagged with the `"f():"` prefix on the target). The `"~ret"` control command
  pops the function return address; void functions return implicitly when their
  container exhausts and push a sentinel that `out` then suppresses.
- **T1 — Single-Level Tunnels** — new `NodeKind.tunnelDivert(target:)` for
  `{"->t->": path}`. `InkEngine` pushes the post-tunnel return address before
  diverting; `"->->"` pops and resumes.
- **T2 — Nested Tunnels** — multi-frame `returnStack` discipline; zero code
  delta beyond T1.
- **T3 — Reference Parameters** — new `NodeKind.variablePointer(name:, contextIndex:)`
  for `{"^var": name, "ci": N}`. `TreeWalker.handleVariableAssignment` writes
  through to the pointed-to variable when the target is an `InkValue.variablePointer`.

A late hotfix landed during pickup: **`InkEngine.initializeGlobalVariables()`
was leaving `state.isEnded = true`** after walking a `global decl` container
that ends with `"end"` — which every real inklecate story does. The fix resets
`state.isEnded = false` and `state.pointer.index = 0` after the walk.

No new source files. All changes are additive extensions of the existing
files: `InkDecoder.swift`, `NodeKind.swift`, `InkEngine.swift`,
`StoryState.swift`, `TreeWalker.swift`. The `Facade/Story.swift` gained a
`cleanOutputWhitespace` filter applied to `continue()` results, mirroring the
inkjs reference runtime.

---

## Business Context

The Intercept playthrough is the Tier-3 ceiling proof — the user-stated goal
of this delivery. Without it, the native engine could not play any non-trivial
Ink story end-to-end. Without C3 (functions) and T1/T2 (tunnels) the runtime
would diverge from the JS oracle on most real stories.

**Outcome:**

| Gate | Result |
|------|--------|
| All 6 slice acceptance suites GREEN | PASS — 33 slice tests |
| The Intercept smoke (loads + canContinue) | PASS |
| The Intercept 15-step save/restore invariant | PASS |
| The Intercept full oracle playthrough (DWD-04 #3) | PASS — 83 oracle lines match line-for-line on the always-choose-0 path |
| No Tier-1 or Tier-2 regressions | PASS — 148 tests / 22 suites all GREEN |

The full-playthrough pass was a bonus — the orchestrator scoped 01-07 to "smoke
+ slice + 15-step invariant only", but the single-line `isEnded` reset unlocked
the entire oracle test as well. A separate follow-on feature is planned for a
non-trivial, choice-strategy-varying playthrough.

---

## Steps Completed

| Step ID | Name | COMMIT time | Result |
|---------|------|-------------|--------|
| 01-01 | C1 — Inline Conditional Text | 2026-06-05T18:10:12Z | PASS |
| 01-02 | C2 — Block and Switch Conditionals | 2026-06-05T18:13:34Z | PASS |
| 01-03 | C3 — Ink Functions | 2026-06-05T18:43:55Z | PASS |
| 01-04 | T1 — Single-Level Tunnels | 2026-06-05T18:49:46Z | PASS |
| 01-05 | T2 — Nested Tunnels | 2026-06-05T18:51:51Z | PASS |
| 01-06 | T3 — Reference Parameters | 2026-06-05T19:03:35Z | PASS |
| 01-07 | Fix global-decl `isEnded` leak; slice + Intercept smoke gate | 2026-06-06 | PASS |

DES integrity verification: **all 7 steps have complete TDD traces** (PREPARE,
RED_ACCEPTANCE, RED_UNIT, GREEN, COMMIT).

---

## Architectural Decisions

D1–D5 from `docs/feature/tier3-conditionals-and-tunnels/design/wave-decisions.md`
landed as designed:

- D1/D2: reuse existing `isConditional` divert pathway for inline + block + switch
  conditionals — no new NodeKind cases for C1/C2.
- D3: `f()` divert classified through the existing `.divert` case using a
  `"f():"` target prefix; `~ret` pops the function-call frame from `returnStack`.
  No new StoryState field for function call frames.
- D4: new `.tunnelDivert` NodeKind; `returnStack` is the shared frame stack for
  both function and tunnel returns; T2 nesting is free.
- D5: new `.variablePointer` NodeKind. The Intercept's reference parameters all
  use `ci == -1` (global scope), so the design's `callFrameVariables` StoryState
  field was not needed — pointer values stored directly in `variablesState`
  with write-through on assignment via the existing dictionary.

DISTILL findings landed too (see
`docs/feature/tier3-conditionals-and-tunnels/distill/upstream-issues.md`):
`"out"` and `"pop"` control commands added to `TreeWalker.handleControlCommand`;
`ci == -1` (not `ci == 0`) treated as the global scope; void-function implicit
returns triggered by container exhaustion when the top return-stack frame has
the `"fnret:"` prefix.

---

## Process Findings (for next delivery)

Discovered at orchestrator pickup, recorded in
`docs/feature/tier3-conditionals-and-tunnels/deliver/upstream-issues.md`:

1. **Acceptance-test gate was not enforced** after the 01-01..01-06 slice
   commits. The execution log recorded each step as COMMIT/PASS, but
   `swift test` showed 41/148 tests red until the 01-07 fix landed. The skill's
   "after each step's COMMIT/PASS, run `tests/acceptance/{feature-id}/`"
   instruction needs stronger enforcement.

2. **Significant working-tree leakage** between commits. After picking up the
   delivery the orchestrator found three production source files
   (`InkDecoder.swift`, `StoryState.swift`, `Story.swift`), all six slice
   fixtures and `TheIntercept.ink.json`, plus the entire prior-wave docs
   directory all uncommitted. These were bundled into the 5 cleanup commits
   `81c1361`..`5a0e24c`. Slice commits should `git status`-verify a clean tree.

3. **Debug `print(...)` statements** were left in production code (one in
   `InkEngine.stepToNextLine`, four in `TreeWalker` for VAR= / VAR? tracing).
   Cleaned up in commit `ea11694`. A pre-commit hook prohibiting `print(` in
   `Sources/SwiftInkRuntime/` (allowing it in tests) would catch this
   automatically.

---

## Test Coverage

- Slice acceptance: `Slice_C1_*` (7), `Slice_C2_*` (8), `Slice_C3_*` (6),
  `Slice_T1_*` (4), `Slice_T2_*` (4), `Slice_T3_*` (4) — 33 tests.
- The Intercept: smoke + 15-step save/restore + full oracle playthrough — 3 tests.
- Unit: `InkEngineTests`, `TreeWalkerTests`, `InkDecoderTests`, `NodeKindTests`
  with one new `InkEngineTests.B12` for the `isEnded` regression.
- Full suite: **148 tests / 22 suites GREEN on macOS-arm64**.

---

## What is NOT done

- **Mutation testing**: skipped per project memory
  (`feedback_mutation_testing.md`) — Muter is unreliable on this Swift project.
- **Non-trivial Intercept playthrough**: deferred to a separate feature. The
  current oracle test always picks choice 0; a deeper proof should vary the
  choice strategy.
- **Linux CI**: still deferred (`feedback_linux_ci.md`); macOS-arm64 only.

---

## Files Changed

| Path | Nature of change |
|------|------------------|
| `Sources/SwiftInkRuntime/Decoder/InkDecoder.swift` | + `"<>"`, `"f()"`, `"->t->"`, `"^var"` classification; named-content child merge |
| `Sources/SwiftInkRuntime/Decoder/NodeKind.swift` | + `.tunnelDivert`, `.variablePointer` cases |
| `Sources/SwiftInkRuntime/Engine/InkEngine.swift` | + pre-dispatch intercepts for `f():`, `->t->`, `->->`, `~ret`; `applyFunctionCall`; tunnel/function return-address builders; `isEnded` reset fix |
| `Sources/SwiftInkRuntime/Engine/StoryState.swift` | + `suppressNextNewline` Codable field |
| `Sources/SwiftInkRuntime/Engine/TreeWalker.swift` | + `out`, `pop`, `du`, `<>`, `nop`, `visit` handlers; variable-pointer write-through; debug-print removal |
| `Sources/SwiftInkRuntime/Facade/Story.swift` | + `cleanOutputWhitespace` filter |
| `Tests/SwiftInkRuntimeTests/Acceptance/Milestone5_*` | + 6 slice suites + Intercept suite |
| `Tests/SwiftInkRuntimeTests/Unit/*` | + Tier-3 unit tests including the B12 isEnded regression |
| `Tests/SwiftInkRuntimeTests/slice-*.{ink,ink.json}` | + 6 inklecate-compiled fixtures |
| `Tests/SwiftInkRuntimeTests/TheIntercept.ink.json` | + Intercept fixture |
| `Package.swift` | + new fixtures as resources |

---

## ADR Impact

None. The five Tier-3 design decisions extend ADR-004 (Call/Return Mechanism)
as anticipated; no new ADRs were raised.

---

## Next

Coverage matrix in `docs/product/architecture/brief.md` rows 22-24, 29-30, 34-35
flip from **UNKNOWN**/**MISSING** to **IMPLEMENTED**. The brief should be updated
in a follow-up commit when the next feature kicks off.
