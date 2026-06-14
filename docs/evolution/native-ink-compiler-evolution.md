# Evolution — native-ink-compiler

**Status**: COMPLETE — milestone S0–S2 and the S3–S6 continuation both shipped; full supported ceiling (matrix rows 1–35) compiles, unsupported set (rows 25–28, 36–39) rejected
**Branch**: `feat/native-ink-compiler-deliver`

This is a cross-feature retrospective archive for the native Ink compiler. The feature is delivered in milestones; each milestone gets its own clearly-headed section appended below. As of the S3–S6 continuation (2026-06-14) all seven slices are delivered.

---

## Milestone S0–S2 — Walking Skeleton, Core Flow, Variables & Expressions

**Date**: 2026-06-14
**Milestone scope**: slices S0, S1, S2 (+ secondary `emitJSON` Ink-JSON sink)
**Test result**: 262 tests total, 0 pre-existing regressions; 8/8 in-scope acceptance scenarios GREEN + 25 example unit tests
**Quality gates**: SwiftLint `--strict` 0 violations (R3/R5) throughout; DES integrity all 6 steps complete traces (exit 0)

### Milestone Summary

This milestone delivers a native, in-process Ink compiler for `SwiftInkRuntime` — eliminating the need to shell out to `inklecate` for the supported subset of the Ink language. Source compiles directly to runtime objects and plays through the existing runtime, with a secondary sink emitting Ink-JSON for round-trip and inspection.

What shipped, by slice:

- **S0 — Walking skeleton**: in-process compile + play of plain text and empty source. No JSON round-trip (D3 deferred), no `inklecate` KPI #4.
- **S1 — Core flow**: knots, stitches, absolute / qualified / relative (`.^`) diverts, glue.
- **S2 — Variables & expressions**: `VAR` / `CONST` / temp declarations; compile-time `CONST` inlining (D6 / DDD-9); Pratt arithmetic parser with postfix emission; variable reads; string interpolation.
- **Secondary — `emitJSON` (D4)**: an Ink-JSON sink alongside the runtime-object emitter.

### Business / Cross-Feature Signal

The native compiler removes the external `inklecate` toolchain dependency from the supported compile path, which is the strategic enabler for the rest of the feature roadmap. The correctness bar is set by an **execution-equivalence oracle**: native compilation is validated against the committed `inklecate` `.ink.json` for the same source, with both played through the same runtime. This makes "do we match the reference compiler?" a mechanically checkable question rather than a judgement call — a pattern worth reusing for any future compiler/transpiler work in this codebase.

### Components Shipped

All co-located under `Sources/SwiftInkRuntime/Compiler/` per **ADR-006**:

| Component | Path | Role |
|---|---|---|
| `CommentEliminator` | `Lexer/CommentEliminator.swift` | Lexer / comment stripping |
| `StringParser` | `Parser/StringParser.swift` | Low-level string scanning primitives |
| `InkParser` | `Parser/InkParser.swift` | Ink structural parser (knots, stitches, diverts, glue) |
| `InkParserExpressions` | `Parser/InkParserExpressions.swift` | Pratt expression parser (arithmetic, interpolation) |
| `CompilerAST` | `AST/CompilerAST.swift` | Compiler AST node model |
| `RuntimeObjectEmitter` | `Codegen/RuntimeObjectEmitter.swift` | Emits runtime objects (primary sink) |
| `JSONEmitter` | `Codegen/JSONEmitter.swift` | Emits Ink-JSON (secondary sink, D4) |
| `CompileError` | `Error/CompileError.swift` | Compile error model |
| `InkCompiler` | `InkCompiler.swift` | Compiler entry point |

Plus an **EXTEND (DDD-2)** to the facade: `StoryBlueprint` gained an internal `init(root:)` so compiled runtime objects can be handed directly to the runtime.

### Correctness Instrument

The execution-equivalence oracle suite is the primary quality instrument: native compile output is compared against the committed `inklecate` `.ink.json` by playing both through the identical runtime and checking line-for-line and choice-for-choice. As of this milestone, 8/8 in-scope acceptance scenarios are GREEN, backed by 25 example-level unit tests; 262 tests run in total with 0 pre-existing regressions.

Mutation testing is **disabled project-wide** (no reliable Swift tool; Muter flaky) — test quality is instead carried by this oracle suite, code review, and the R1/R3/R5 SwiftLint boundary gates. This is a durable project constraint, not a milestone-specific deferral.

### Lessons Learned (Quality-Gate History)

- **Roadmap review REJECTED once** — step 02-01 had to be reframed as an *enabling* step rather than a deliverable in its own right. Fixed before proceeding. Signal: enabling/scaffolding work should be labelled as such in the roadmap so reviewers don't read it as user-facing scope.
- **Adversarial review found one BLOCKER** — escaped-quote handling was wrong in both `CommentEliminator` and the `InkParserExpressions` string scans. Fixed via TDD (RED reproducing the escaped-quote case first). Signal: string-scanning edges (escapes, nesting) are the highest-yield place to point an adversarial reviewer in a parser.
- **L1–L6 refactor removed stale `// SCAFFOLD: true` headers** — the `.scaffold` enum case was deliberately **kept** for the still-future S3–S6 work; only the misleading per-file headers were removed. Signal: distinguish "scaffold marker that's now a lie" from "scaffold mechanism still needed downstream."
- **Boundary gates held**: SwiftLint `--strict` reported 0 violations (R3/R5) throughout; DES integrity produced complete traces for all 6 steps (exit 0).

### Deferred / Out of Scope (Future Work)

The feature is **not complete**. The following are explicitly deferred and not shipped in this milestone:

| Slice / item | Deferral note |
|---|---|
| S3 — choices / gathers | Gated on the weave spike (**ADR-008**); `WeaveResolver` not yet shipped |
| S4 — ceiling, TheIntercept e2e | Future |
| S5 — doc-vs-compiler consistency | Future |
| S6 — unsupported-construct rejection | Reject-list not yet shipped |
| `SourceReader` / `compile(fileURL:)` | Not yet shipped — current entry is in-process source only |
| `swift-tools-version` raise (C-7) | Not yet applied |

### Source-of-Truth Pointers

| Artifact | Path |
|---|---|
| Feature delta (DELIVER sections) | `docs/feature/native-ink-compiler/feature-delta.md` |
| Roadmap (step plan) | `docs/feature/native-ink-compiler/deliver/roadmap.json` |
| Execution log (step history) | `docs/feature/native-ink-compiler/deliver/execution-log.json` |
| Measured KPI baselines | `docs/product/kpi-contracts.yaml` (`measured_baselines`) |
| Architecture brief (Component Inventory) | `docs/product/architecture/brief.md` |
| Compiler sources | `Sources/SwiftInkRuntime/Compiler/` |

---

## Milestone S3–S6 — Weave, Ceiling, Feature Reference, Unsupported Rejection (feature complete)

**Date**: 2026-06-14
**Milestone scope**: slices S3 (choices/gathers/weave), S4 (ceiling: conditionals/functions/tunnels/ref-params/tags), S5 (feature-reference consistency), S6 (unsupported-construct rejection)
**Commits**: `2e714a2..HEAD` (06-01 `a048f59`, 06-02 `425946c`, 03-01 `1cd68dd`, 04-01 `3050e55`, 04-02 `317e3c7`, S4 suite `4928bee`, 05-01 `575b1d7`, refactor `2f0454a`)
**Test result**: full suite **280 tests GREEN**, 0 pre-existing regressions (the TheIntercept S4 end-to-end test is intentionally `.disabled` — see below)
**Quality gates**: SwiftLint `--strict` 0 violations (R1/R3/R5) throughout; adversarial review APPROVED (0 blockers, 0 testing-theater); DES integrity exit 0 (all 12 steps complete RED/GREEN/COMMIT traces); mutation testing SKIPPED (disabled project-wide)

### Milestone Summary

This milestone completes the native compiler to the **full supported ceiling**. With it, supported stories — branching, full-logic, up to (but excluding) The Intercept's sequence — compile in pure Swift and play oracle-identical, and every unsupported construct is rejected with a clear, located error. What shipped, by slice:

- **S6 — unsupported rejection (landed first, as a guardrail)**: a `UnsupportedConstructDetector` rejecting variable-text sequences/cycles/once/shuffle and thread/LIST/RANDOM/EXTERNAL with a located `.unsupportedConstruct` error *before* codegen, so no unsupported input could slip through silently during S3/S4 development. 8/8 rejects located + construct-named.
- **S3 — choices / gathers / weave**: a general `WeaveEmitter` resolver handling nested weaves, labeled and multiple gathers, sticky/plain/labeled choices, and sealed weaves. 4/4 weave fixtures GREEN.
- **S4 — supported ceiling**: conditionals (inline/block/switch, new `ConditionalEmitter`) + tags, then functions + inline calls, tunnels, and reference parameters.
- **S5 — feature reference (US-07)**: `docs/product/ink-feature-reference.md`, statuses verified against actual compiler behaviour (13/13 consistency cases GREEN).
- **L1–L6 refactor** of the S3–S6 compiler code closed the milestone.

### Highest-Risk Outcome — the Weave Resolver

The weave resolver (S3) was the research- and DISCUSS-flagged **single highest-risk algorithm** for the whole feature, and the four-fixture corpus (flat / nested / labeled-gather / sealed) was designated the ADR-008 spike gate. **Outcome: it landed clean — 4/4 fixtures oracle-identical (line-for-line and choice-for-choice).** A notable simplification: the choice-flag / invisible-default encoding (originally a standalone roadmap step, D6) turned out to be validated by the same S3 oracle corpus per DDD-9 and was **folded into the resolver step** rather than shipped separately — the encoding was correct as soon as the resolver was correct.

### The Sequence Parity-Gap Discovery (upstream finding)

The DESIGN brief states The Intercept exercises Parts 1–4 "without using sequences." This is **incorrect**: `TheIntercept.ink` line 86 uses a variable-text sequence `{|I rattle my fingers on the field table.|}`. Because the compiler correctly rejects sequences (rows 25–28), The Intercept cannot be natively compiled today, so the native-compile **e2e was descoped** (user-approved) and its S4 test committed `.disabled`.

The deeper cross-feature lesson is a **compiler/runtime parity gap**: the *runtime already plays this construct* because inklecate lowers `{|...|}` to a **visit-count switch** (visit + MIN + `==` + conditional diverts) — primitives the runtime executes (this is why the Milestone5b playthrough renders the first 100 lines, with line 86 empty on first visit). So deterministic variable-text (sequence/cycle/once) is a future-work candidate the compiler *could* lower the same way; only shuffle additionally needs RANDOM (genuinely runtime-unsupported). User decision (2026-06-14): keep sequences rejected as specced this pass; do not expand the supported set.

### Lessons Learned (Quality-Gate History)

- **Land the rejection guardrail before the codegen slices.** Shipping S6 (`UnsupportedConstructDetector`) ahead of S3/S4 meant no unsupported construct could compile to silent wrong output while the harder slices were in flight — the cheapest possible insurance against the feature's #1 anxiety (silent divergence).
- **The highest-risk algorithm fell to a tight oracle corpus.** Pinning the weave resolver to four targeted fixtures (flat/nested/labeled-gather/sealed) as an explicit spike gate let the highest-risk work land in one step with no escapes.
- **Two latent codegen bugs surfaced via RED-first oracle tests, both in S4**: (1) a **bool-literal emission bug** — `true`/`false` were not lowered to the runtime's expected literal form (found and fixed in `ConditionalEmitter`); (2) a **knot-marker bug** — two-equals (`==`, a stitch/operator) was being confused with three-equals (`===`, a knot/function marker) in the parser. Both are classic parser/codegen edge cases that an always-happy-path test would never have caught — the oracle's line-for-line check is what flushed them out.
- **Brief claims are not ground truth.** A documented assumption in the architecture brief ("no sequences") was contradicted by the actual fixture; the oracle/reject machinery caught the contradiction. Signal: validate corpus claims against the corpus, not the prose.
- **Boundary gates held**: SwiftLint `--strict` 0 violations; adversarial review APPROVED with 0 blockers; DES integrity exit 0 across all 12 steps.

### Source-of-Truth Pointers (this milestone)

| Artifact | Path |
|---|---|
| Feature delta (DELIVER S3–S6 continuation) | `docs/feature/native-ink-compiler/feature-delta.md` |
| Feature reference (US-07) | `docs/product/ink-feature-reference.md` |
| Roadmap (12-step plan + scope_note) | `docs/feature/native-ink-compiler/deliver/roadmap.json` |
| Execution log (step history) | `docs/feature/native-ink-compiler/deliver/execution-log.json` |
| Architecture brief (Feature Coverage Matrix + Component Inventory) | `docs/product/architecture/brief.md` |
| Compiler sources | `Sources/SwiftInkRuntime/Compiler/` |
