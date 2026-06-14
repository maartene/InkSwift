# ADR-010: Variable-Text Lowering (sequence / cycle / once-only)

## Status

Accepted (2026-06-14)

## Context

The native Ink compiler (`Compiler/` layer inside `SwiftInkRuntime`, ADR-006) covers
the runtime's supported ceiling (Feature Coverage Matrix rows 1–35) but **rejects**
all four variable-text alternative forms (rows 25–28) via
`UnsupportedConstructDetector`. Three of those forms are **deterministic** and the
runtime can already play the shape inklecate lowers them into:

- **sequence** `{a|b|c}` (row 25) — advance per visit, clamp on the last stage
- **cycle** `{&a|b}` (row 26) — advance per visit, wrap via modulo over the stage count
- **once-only** `{!a|b}` / bare `{|x|}` (row 27) — advance once, then fall silent

Only **shuffle** `{~a|b}` (row 28) additionally needs `RANDOM`, a genuine runtime gap,
and stays rejected (decision D-A).

The feature `compiler-variable-text` closes this documented compiler↔runtime parity
gap. The blocker is concrete: `TheIntercept.ink` line 86 `{|I rattle my fingers on the
field table.|}` is a bare once-only/sequence form, so the flagship fixture's
native-compile e2e test is currently descoped.

### Ground truth — inklecate's lowering (verified against the real compiler)

All three forms lower to an anonymous container with `#f:5` (`Visits | CountStartOnly`,
so `visit` reports a 0-based own-entry index — 0 on first play). The body computes the
index, then dispatches to one named stage container per stage via the runtime's
existing `visit` / `du` / `==` / conditional-divert vocabulary. Each stage starts with
`pop` (discarding the duplicated index), emits its text (if any), then diverts to a
shared continuation. The three forms differ **only** in three parameters:

| Form | `OP` | `BOUND` | append empty trailing stage? |
|---|---|---|---|
| sequence (S stages) | `MIN` | `S − 1` (last index) → advance then **clamp** | no |
| cycle (S stages) | `%` | `S` (stage count) → **wrap** via modulo | no |
| once-only (S source stages) | `MIN` | `S` (last index after append) → advance then **blank** | **yes** (one empty stage) |

Therefore **once = sequence + one appended empty final stage**, and **bare `{|x|}` is a
plain sequence** whose `|`-split yields empty first/last stages (`["", "x", ""]`).

The engine supports every primitive this requires, with **zero runtime change**:
`visit` (`TreeWalker.swift:180`), `du` (`:144`), `MIN`/`MAX` (`:287`), `%` (`:274`),
`nop` (`:166`), `pop`/`ev`/`/ev` (control commands, `InkDecoder.swift:8`), plus `==`,
conditional diverts (`"c":true`), the `#f` visit-count flag, and named containers — all
proven in production by `ConditionalEmitter` and the Tier-2/Tier-3 work.

## Decision

Lower the three deterministic variable-text forms to inklecate's read-count
visit-switch shape via **one new parametrized codegen emitter**, `VariableTextEmitter`
(`Compiler/Codegen/`), invoked from `RuntimeObjectEmitter.lowerBody` exactly parallel
to `ConditionalEmitter`. The emitter:

1. Is a stateless `enum` with static methods (house style — like `ConditionalEmitter`
   and `WeaveEmitter`), paradigm OOP value-type.
2. Takes `(op, bound, appendEmptyStage)` plus the parsed stages and lowers them to:
   - a dispatch prologue: `ev visit BOUND OP /ev` then, per stage,
     `ev du <index> == /ev` + conditional divert to that stage's named container,
     followed by `nop`;
   - one **named stage container** per stage (`seq{N}-s{I}`) holding `pop`, the stage's
     `^text` (omitted for an empty stage), and a divert to the shared continuation;
   - one shared continuation container `seq{N}-end` holding the line's trailing
     segments and the rest of the enclosing body (the same rejoin contract
     `ConditionalEmitter` uses).
3. Uses **absolute-qualified named stage containers** (registered into the caller's
   `named` collector) — never relative `.^.sN` caret arithmetic — and stamps the
   dispatch container with `#f:5` so the `visit` index is the read count.
4. The three forms map to: sequence → `(MIN, lastIndex, false)`; cycle →
   `(%, stageCount, false)`; once → `(MIN, lastIndex-after-append, true)`.

`UnsupportedConstructDetector` is changed so its inline scan rejects **only** shuffle
(`~` marker); sequence/cycle/once pass through to the parser. The inline-conditional
discriminator (top-level `:` ⇒ route to `ConditionalEmitter`) is preserved unchanged.

A new `ContentSegment.variableText(mode:stages:)` AST case and a parse rule
(`|`-split on the brace-group body at top-level, mode from the leading marker) carry
the construct from parser to codegen, parallel to the existing
`ContentSegment.conditional`.

## Alternatives Considered

### Alternative 1 — Parser-level desugar into the conditional AST (rejected)

Rewrite each variable-text group into an equivalent `conditionalBlock` AST during
parsing, reusing `ConditionalEmitter` unchanged.

- **Pro**: no new emitter; one fewer codegen component.
- **Con**: variable-text dispatch is driven by the `visit`/index read count and `MIN`/`%`
  numeric reduction — *not* by a per-arm boolean guard. Desugaring would have to synthesise
  an `ev visit … == /ev` guard per stage and an index variable inside the parser, pushing
  codegen-shaped knowledge (the `#f:5` flag, the `du`/`pop` discipline) up into the parser
  and violating the parser's role as a structural reader. Rejected.

### Alternative 2 — Extend `ConditionalEmitter` to also handle variable-text (rejected)

Add a variable-text path to the existing conditional emitter.

- **Pro**: reuses the branch-container/`-end`-continuation machinery directly.
- **Con**: `ConditionalEmitter` dispatches on a boolean guard popped from the eval stack;
  variable-text dispatches on a computed visit index reduced by `MIN`/`%`. Folding both
  into one emitter muddies a single-responsibility component and would push it past the
  Calisthenics small-entity rule — the exact reason `ConditionalEmitter` and
  `WeaveEmitter` are separate today. Rejected in favour of a parallel, one-concern emitter
  that *reuses the boundary pattern* (named containers + `-end` rejoin via `lowerBranch`)
  without sharing the body.

### Alternative 3 — Byte-replicate inklecate's relative `.^.sN` addressing (rejected)

Emit the exact container tree inklecate produces, including relative caret-path stage
addressing.

- **Pro**: structurally identical to the oracle JSON; trivial structural diff.
- **Con**: D5 correctness is **Level-1** (PLAY/line equivalence), which grants full
  tree-shape freedom; structural match is NOT required. Relative `.^.sN` arithmetic is the
  fragile caret-math the house style deliberately abandoned in `ConditionalEmitter` and
  `WeaveEmitter` in favour of absolute-qualified named containers. Reintroducing it for one
  emitter would diverge from the established convention for no correctness benefit. Rejected.

## Consequences

### Positive

- Closes the deterministic variable-text parity gap; rows 25–27 move MUST-REJECT →
  MUST-COMPILE. The descoped `TheIntercept.ink` native-compile e2e test is re-enabled.
- **Zero runtime / engine / Decoder / Facade change** (KPI #4, guardrails D8 / R5). The
  lowering reuses only primitives the engine already executes.
- One parametrized routine keeps the three forms DRY; the differences are three explicit
  parameters, removing cross-form drift risk.
- Established house pattern (named absolute containers + `-end` rejoin) keeps the new
  emitter consistent with `ConditionalEmitter`/`WeaveEmitter`; no new addressing style.
- Correctness is oracle-guarded at Level-1 (hermetic execution-equivalence), the same gate
  every supported construct already passes.

### Negative / Trade-offs

- One new codegen component, one new AST `ContentSegment` case, and one parse rule (the
  minimum CREATE NEW surface; everything else is REUSE/EXTEND).
- Boundary fixtures (clamp-at-last, modulo-wrap, empty-trailing-stage, bare `{|x|}`) must
  be enumerated explicitly in DISTILL/DELIVER so the off-by-one risk at clamp/wrap
  boundaries is caught (carried-over DISCUSS risk).
- The `UnsupportedConstructDetector` gate change is a regression-sensitive edit: shuffle
  must still reject. A shuffle-reject regression guard is required in every slice (already
  in the DISCUSS AC).

### Neutral

- No new dependency, no `Package.swift` change, no new driving/driven port. The existing
  compile entry point's accepted set widens (rows 25–27 now yield a runnable story); the
  port signature is unchanged.
