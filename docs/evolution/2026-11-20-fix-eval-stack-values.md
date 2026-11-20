# Evolution — fix-eval-stack-values

**Status**: COMPLETE. Three open reference-fidelity issues (#46, #44, #41) traced to one root cause and fixed in four DELIVER steps on `main`, shipped together in **2.2.2**. No public API change.
**Date**: 2026-11-20
**Issues**: #46, #44, #41 (closed by the release). Filed during delivery: #47 (native compiler rejects the string literal `"!"`).
**Predecessor**: `docs/evolution/2026-11-20-reference-fidelity-backlog.md`. #41, #44 and #46 were all found while delivering or reviewing it; this feature reuses its `InkRuntimeError` path (2.1.6) and `BinaryNativeFunction` coercion (ADR-024 §3).

Waves: bugfix flow (root-cause analysis → maintainer review → DELIVER). No DISCUSS, DESIGN or DISTILL wave; the issue repros, compiled by inklecate and used as oracle fixtures, were the acceptance tests. The durable lesson: **a silent guard hides the bug that made it necessary.** The stack-underflow guards existed because a missing variable pushed nothing; removing that cause let every guard become a loud error, and the review then found four more silent pops nobody had listed.

---

## Root cause

The runtime's evaluation stack did not hold the values the C# reference holds, and the operator helpers in `TreeWalker` quietly covered for it:

| Issue | Symptom | Cause |
|---|---|---|
| #46 | `Value: {y}.` printed `Value: .` for a temp whose declaration was skipped | `handleVariableReference` pushed nothing; C# pushes `0` and warns |
| #44 | A story string `"void"` was never printed | The string `"void"` was the no-value sentinel; `out` dropped it. The JSON `void` token was a no-op, so `~ saved = bare()` also left `saved` unchanged |
| #41 | `{not "a"}` printed `false`, `{-true}` printed `true`, `{1.0 / 0.0}` printed `0`, `{1 / 0}` printed `0` | Unary natives had no coercion or error path; `/` and `%` special-cased a zero divisor to `0.0` |

## Steps

| Step | Commit | Change |
|---|---|---|
| 01-01 | 3589fc8 | A missing variable pushes `.int(0)` (Story.cs VariableReference). Fixes #46 |
| 01-02 | fbe6662 | `InkValue.void`: the `void` token, an implicit function return and `srnd` push it; `out` skips only it; `->->` pops it; bare `~ return` lowers to `ev void /ev ~ret`. Fixes #44 |
| 01-03 | c7b0286 | `UnaryNativeFunction` with C# coercion (bool → int) and `Cannot perform operation` errors; void operands refused before coercion; IEEE float `/` and `%`; `INT` saturates to the 32-bit range; integer division by zero and stack underflow are runtime errors. Fixes #41 |
| 01-04 | aece25d | Review follow-ups: every evaluation-stack pop (`->->`, `pop`, `out`, `srnd`, conditional divert and choice conditions) reports a short stack; total native-function lookup (`NativeFunction.operation`); accurate comments and differences doc |

## Maintainer decisions

- **Integer division or modulo by zero** reports `Attempted to divide by zero.` and ends the flow. inklecate crashes with an unhandled `DivideByZeroException` (inkle/ink#843, open and unanswered since 2023), so there is no story behaviour to copy. Recorded on `InkRuntimeError.divideByZero` and in `differences-from-inklecate.md`.
- **A short evaluation stack** is a reported runtime error, not a silent skip and not a `preconditionFailure`: `Story(json:)` accepts JSON from any source and must not crash the host.
- **One delivery, one release** for the three issues, since they share the cause and the code.

## Behaviour changes users may notice

- Stories that played on with a made-up value now stop with an error: operators with one operand on a string, any operator on a void function result, integer division by zero.
- `INT()` of a float beyond the 32-bit range clamps, matching inklecate.
- A save holding a void value (`"type":"void"`) can't be read by builds before 2.2.2. An older save's `"void"` string now restores as text and prints.

## Known gaps left open

- **Integer width**: InkSwift integers are 64-bit; ink's are 32-bit and wrap (`2147483647 + 1` is `-2147483648` in inklecate). Overflow of 64-bit arithmetic traps. Predates this feature; found in review.
- **`->-> target` on the native path** compiles silently to an ordinary divert and the tunnel never returns. On inklecate JSON the target is popped and ignored. Documented in `differences-from-inklecate.md`.
- **Runtime warnings** (#39): the missing-variable warning is not emitted; `TestTempNotFound` stays disabled for that alone.
- `BinaryNativeFunction.byFunction` is kept only for `NativeFunctionCatalogTests`.

## Quality gates

- Every step: regression tests RED for the business reason, then the full suite green through `.githooks/pre-commit` (final: 973 Swift Testing tests in 133 suites, 31 XCTest).
- Manual mutation testing per step (19 mutations); every survivor was killed by a new assertion or shown equivalent in its commit message.
- Adversarial review (`nw-software-crafter-reviewer`): 0 blockers, 7 should-fix; the in-scope ones closed in 01-04.
- `des-verify-integrity`: all 4 steps have complete traces.
- Upstream conformance backlog: no test changed state; `TestTempNotFound`'s reason narrowed to runtime warnings (#39).
