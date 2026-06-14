# DESIGN Wave Decisions — compiler-variable-text

**Feature**: compiler-variable-text | **Wave**: DESIGN | **Scope**: Application/component
**Mode**: PROPOSE | **Density**: lean | **Architect**: Morgan (nw-solution-architect)
**Date**: 2026-06-14 | **Status**: DESIGN complete — pending peer review before DISTILL

Predecessor: `native-ink-compiler` (delivered). This is a compiler-only follow-on
increment that lowers the three deterministic variable-text forms (matrix rows 25–27).

---

## Key Decisions

| # | Decision | Verdict | ADR |
|---|---|---|---|
| 1. Lowering placement | New codegen emitter `VariableTextEmitter` invoked from `RuntimeObjectEmitter.lowerBody`, parallel to `ConditionalEmitter`/`WeaveEmitter`. (Parser-desugar and extend-ConditionalEmitter rejected.) | Option A | ADR-010 |
| 2. Shared vs separate routine | ONE parametrized routine over `(op, bound, appendEmptyStage)`. | Option A | ADR-010 |
| 3. Stage-container shape / addressing | Absolute-qualified named stage containers `seq{N}-s{I}` + shared `seq{N}-end`; `#f:5` on the dispatch container; `visit`/`du`/`==`/conditional-divert dispatch. No relative `.^.sN` caret arithmetic. | Option A | ADR-010 |
| 4. Empty-stage representation | A stage container with `pop` + divert and no `^text`. Once-only appends one such stage; bare `{\|x\|}` is a plain sequence (`\|`-split → empty first/last stages). | Resolved | ADR-010 |
| 5. Gate change | `UnsupportedConstructDetector` rejects ONLY shuffle (`~`); sequence/cycle/once pass through. Inline-conditional `:` discriminator preserved. | Accepted | ADR-010 |

---

## Architecture Summary

The three deterministic variable-text forms lower to inklecate's read-count
visit-switch shape via one parametrized stateless `enum` emitter. Per form, the dispatch
container (flagged `#f:5`, so `visit` yields the 0-based read count) computes the stage
index and conditionally diverts to one named stage container per stage; each stage emits
its text (if any) and rejoins a shared `-end` continuation. The forms differ only in:

| Form | OP | BOUND | append empty stage? |
|---|---|---|---|
| sequence `{a\|b\|c}` | `MIN` | last index (S−1) → clamp | no |
| cycle `{&a\|b}` | `%` | stage count (S) → wrap | no |
| once-only `{!a\|b}` / bare `{\|x\|}` | `MIN` | new last index (S after append) → blank | yes (1); bare form: no append, empty edge stages |

No new runtime/engine/Decoder/Facade code, no new dependency, no new port, no new
`NodeKind` case. The emitter reuses `ConditionalEmitter`'s named-container + `-end`-rejoin
boundary pattern (copied pattern, not shared code).

---

## Reuse Analysis

**CREATE NEW = 3** | **EXTEND = 3** | **REUSE AS-IS = 7.**

- **CREATE NEW**: `VariableTextEmitter` (`Compiler/Codegen/`); `ContentSegment.variableText` case + `VariableTextMode` enum (`Compiler/AST/CompilerAST.swift`); variable-text parse rule (`Compiler/Parser/InkParser*.swift`).
- **EXTEND**: `RuntimeObjectEmitter.lowerBody` (+ `.variableText` dispatch branch); `UnsupportedConstructDetector` (narrow reject to shuffle); the parser file hosting the new rule.
- **REUSE AS-IS**: `ConditionalEmitter` (pattern template), `ContainerNode`, `NodeKind`, `branchLowerer`/`lowerBody` recursion, the engine ops (`visit`/`du`/`MIN`/`%`/`nop`/`pop`/`==`/conditional-divert), the oracle harness/corpus, `TheIntercept.ink` + oracle.

Full table: `docs/feature/compiler-variable-text/feature-delta.md`
§ `Wave: DESIGN / [REF] Reuse Analysis`.

---

## Technology Stack

No change. Pure Swift over the existing internal `NodeKind`/`ContainerNode` types.
No `Package.swift` edit, no new dependency, no new tooling. Enforcement is the existing
SwiftLint `custom_rules` R1/R3/R5 gates + Swift access control (R2).

---

## Constraints

- Compiler-only diff. No `Engine/`, `Decoder/`, `Facade/` execution change; frozen
  `InkSwift` untouched (D8 / KPI #4).
- R2: `NodeKind`/`ContainerNode` stay internal. R5: `Compiler/` may import `Decoder/`
  node types, may NOT import `Engine/`, may NOT call `JSONSerialization`.
- Paradigm: OOP value-type — `VariableTextEmitter` is a stateless `enum` with static
  methods (like `ConditionalEmitter`/`WeaveEmitter`).
- Correctness gate: hermetic Level-1 execution-equivalence (committed `.ink.json`
  through the pure-Swift `Story`).
- Shuffle (row 28) must still reject with a located error — regression-guarded in every
  slice.

---

## Upstream Changes

None. No DISCUSS decision is reversed; the ground truth confirms the "zero runtime
change" and "one shared routine" premises. No back-propagation required.

---

## Handoff to DISTILL

- ADR-010 written and Accepted; indexed in `brief.md` (both ADR Index tables).
- SSOT updated: `### compiler-variable-text (Feature Addition)` subsection in `brief.md`.
- Deferred to DISTILL: enumerate the boundary-fixture corpus (OQ-1) — clamp-at-last,
  modulo-wrap, empty-trailing-stage, bare `{\|x\|}`, 2-stage once vs 2-stage sequence,
  plus the shuffle-reject regression fixture.
- External integrations: none. Contract testing not applicable.
