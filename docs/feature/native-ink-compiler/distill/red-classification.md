# RED Classification — native-ink-compiler (DISTILL pre-DELIVER gate)

**Date**: 2026-06-14 | **Wave**: DISTILL | **Gate**: fail-for-the-right-reason
**Command**: `swift test` | **Result**: every compiler scenario fails RED (missing
functionality), zero BROKEN (no import/fixture/setup failure). DELIVER reads this
file at PREPARE/RED to confirm RED is genuine.

## Run summary

- Total: **233 tests in 46 suites**. Pre-existing runtime suite + dependents:
  **all GREEN** (no regression from the new `Compiler/` files / Package.swift edits).
- New compiler acceptance tests: **37** (36 RED + 1 GREEN guardrail). **52** assertion
  issues recorded — all trace to `CompileErrorKind.scaffold`.

## Per-suite classification

| Suite | Tests | Classification | Why RED (right reason) |
|---|---|---|---|
| `Compiler_S0_WalkingSkeletonTests` | 4 | ✅ RED `MISSING_FUNCTIONALITY` | `InkCompiler.compile`/`Story(inkSource:)`/`emitJSON` (secondary D4 sink) throw `.scaffold`; oracle fixtures load fine. |
| `Compiler_S1_CoreFlowTests` | 2 | ✅ RED `MISSING_FUNCTIONALITY` | compile throws `.scaffold` before the equivalence `#expect`. |
| `Compiler_S2_VariablesTests` | 2 | ✅ RED `MISSING_FUNCTIONALITY` | same; oracle renders `Total: 13` / `Math: 14` as expected. |
| `Compiler_S3_ChoicesGathersTests` | 4 (parametrized weave corpus) | ✅ RED `MISSING_FUNCTIONALITY` | weave-spike corpus; compile throws `.scaffold`. |
| `Compiler_S4_CeilingTests` | 3 | ✅ RED `MISSING_FUNCTIONALITY` | incl. native `TheIntercept.ink` e2e; compile throws `.scaffold`. |
| `Compiler_S5_FeatureReferenceConsistencyTests` | 13 (5 supported + 8 unsupported) | ✅ RED `MISSING_FUNCTIONALITY` | supported throw `.scaffold`; unsupported get `.scaffold` ≠ `.unsupportedConstruct`. |
| `Compiler_S6_UnsupportedRejectionTests` | 8 (parametrized reject corpus) | ✅ RED `MISSING_FUNCTIONALITY` | each asserts kind=`.unsupportedConstruct`, construct named, line>0; scaffold throws `.scaffold`. |
| `Compiler_NoInklecateGuardrailTests` | 1 | ✅ GREEN (guardrail) | source-guard finds no `Process`/inklecate in production `Compiler/`; KPI #4 holds and must keep holding. |

## Categories observed

- `MISSING_FUNCTIONALITY` (correct RED): **36/36** failing tests.
- `IMPORT_ERROR` / `FIXTURE_BROKEN` / `SETUP_FAILURE` (wrong RED): **0** — grep for
  `Missing source fixture` / `Missing oracle fixture` / `could not find resource`
  returned nothing; all `.ink` and `.ink.json` resources resolve via `Bundle.module`.
- `WRONG_ASSERTION` / `OBSERVABLE_NOT_AT_PORT`: **0** — assertions are on port-exposed
  observables only (emitted lines via `Story.continue()`; `CompileError.kind/construct/line`).

## Gate verdict

**PASS — handoff to DELIVER is unblocked.** Every scenario fails because the
implementation is missing (`InkCompiler` scaffold), not because of a test bug. The
one green test is an intentional guardrail (KPI #4), not a feature scenario.

DELIVER removes the `.scaffold` sentinel (`grep -rn "SCAFFOLD: true" Sources/`) slice
by slice; each slice's suite flips GREEN as its codegen lands. The walking skeleton
(S0) is RED here by design — no SPIKE promoted it — and is the first to go GREEN.
