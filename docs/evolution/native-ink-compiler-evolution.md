# Evolution — native-ink-compiler

**Status**: IN PROGRESS — milestone S0–S2 shipped; S3–S6 deferred (see "Deferred / Out of Scope")
**Branch**: `feat/native-ink-compiler-deliver`

This is a cross-feature retrospective archive for the native Ink compiler. The feature is delivered in milestones; each milestone gets its own clearly-headed section appended below. Slices S3–S6 remain future work — the feature is **not** fully complete.

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
