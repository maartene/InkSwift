# DISTILL RED Classification — compiler-variable-text

**Date**: 2026-06-15 | **Gate**: pre-DELIVER fail-for-the-right-reason
**Convention**: per CLAUDE.md, new ATs are authored `.disabled` (skipped, suite stays
green for per-step trunk commits). Genuine RED is realised in DELIVER the moment a step
removes its AT's `.disabled` trait. This file classifies the failure mode each AT WILL
exhibit at that point, so DELIVER confirms RED is genuine before going GREEN.

Full-suite snapshot at DISTILL hand-off: `swift test` → **288 tests, 0 failures**
(VT1/VT2/VT3 ATs skipped; VT0 shuffle guard passing). No `IMPORT_ERROR` / `FIXTURE_BROKEN`
/ `SETUP_FAILURE` — every AT compiles against the existing `InkCompiler.compile`,
`CompilerOracle`, `CompileError`, `Story` API, and every referenced fixture exists.

| AT (suite → scenario) | DELIVER slice | Expected RED mode when enabled | Why it is correct RED |
|---|---|---|---|
| VT1 → once-only emits once | slice-01 | `MISSING_FUNCTIONALITY` | `{!a\|}` currently rejected by `UnsupportedConstructDetector`; `compileAndPlay` throws `CompileError` until the gate narrows + emitter lands |
| VT1 → bare `{\|x\|}` sequence | slice-01 | `MISSING_FUNCTIONALITY` | same — bare form currently rejected; no lowering yet |
| VT2 → 3-stage clamp | slice-02 | `MISSING_FUNCTIONALITY` | sequence currently rejected; emitter clamp path not yet implemented |
| VT2 → 2-stage clamp | slice-02 | `MISSING_FUNCTIONALITY` | same |
| VT2 → mixed cond+VT (OQ-3) | slice-02 | `MISSING_FUNCTIONALITY` | sequence within mixed body rejected until lowering lands |
| VT3 → 2-stage wrap | slice-03 | `MISSING_FUNCTIONALITY` | cycle currently rejected; modulo-wrap parameter not yet implemented |
| VT3 → 4-stage modulo wrap | slice-03 | `MISSING_FUNCTIONALITY` | same |
| S4 → TheIntercept e2e (re-pointed) | slice-04 | `MISSING_FUNCTIONALITY` | line-86 once-only rejected until slices 01-03 land; whole-fixture native compile blocked |

**VT0 shuffle guard** is intentionally ENABLED and GREEN today; it is the always-on
tripwire that reds if any slice's gate change lets shuffle through. Not a RED candidate.

**DELIVER reads this file at PREPARE/RED phase** to confirm each enabled AT fails for
missing functionality, not a test/setup defect.
