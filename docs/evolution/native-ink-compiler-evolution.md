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

---

## Milestone — Weave-Label Read-Count Addressing

**Date**: 2026-06-15
**Milestone scope**: a read-count addressing subsystem for the native compiler — dotted read-count references to named weave labels AND named knots/stitches (`{knot.label: …}`, `{knot.stitch: …}`) lower to a runtime `.readCount(resolvedPath)` node. Implements **ADR-011 (Option B, AMENDED 2026-06-15)**.
**Commits**: `db4bcef..c47b2a0` on `main` (5 steps: 01-01, 02-01, 02-02, 02-03, 03-01) — trunk-based, committed step-by-step as each went green
**Test result**: full suite **323 tests GREEN**; the RED-pin AT `a dotted read-count reference to a named stitch lowers to a read-count node` is GREEN
**Quality gates**: SwiftLint `--strict` boundary rules R1/R3/R5 + WL-D7 ("no runtime change") held throughout — the slice is confined entirely to `Compiler/`; adversarial review **APPROVED** (0 defects, 0 testing theater, no test weakening; 1 advisory only — ~3 tests over a heuristic budget); DES integrity **exit 0** (all 5 steps complete RED/GREEN/COMMIT traces); mutation testing disabled project-wide (CLAUDE.md)

### Milestone Summary

This slice delivers the read-count addressing subsystem that ADR-011 designed, entirely within `Compiler/` with zero runtime/Engine/Decoder change (the read-count / `CNT?` / CountVisits machinery was already implemented; this slice only makes the compiler *emit* into it). What shipped, by step:

- **01-01** — Parse a choice's `(label)` weave-label and `{condition}` guard. The AST `choice` case gains `weaveLabel` + `condition` (mirroring the existing gather `(label)` parsing).
- **02-01** — Key labelled choice outcome containers by their label (`label ?? c-N`), mirroring how gathers are already keyed. A labelled choice becomes addressable by its name segment in the absolute path.
- **02-02** — A discovery pre-pass (= inklecate's `Weave.ResolveWeavePointNaming`) plus a `weaveLabelPaths` table on `LoweringContext`. Labelled-only; collects the SET of labels that are read-count-referenced; reuses the resolver's already-cached absolute paths (never re-derives).
- **02-03** *(scope-expanded, user-approved)* — The expression parser now accepts dotted identifiers, and `lowerExpression` emits `.readCount(resolvedPath)` resolving a dotted reference against the weave-label table AND knot/stitch absolute paths; a miss falls through to `.variableReference` (today's behaviour, matching the original). Re-enabled the RED-pin AT (GREEN).
- **03-01** *(scope-expanded, user-approved)* — Sets the `0x1` CountVisits flag on exactly the read-count-referenced targets (labelled weave containers AND referenced knots/stitches); lowers `{condition}`-guarded choices; plus two surgical parser fixes (gather `- -> target` mis-level in `consumeMarkers`; `text[]suffix` empty-bracket choice split).

### The Two User-Approved Scope Expansions (ADR-011 back-propagation)

ADR-011 originally scoped read-count addressing to **weave labels only**. During DELIVER step 02-03, direct inspection of `TheIntercept.ink` found the flagship e2e requires **two** read-count shapes, not one: knot.**choice-label** (`harris_demands_component.cant_talk_right`, `start.delay` — covered by the original design) AND knot.**stitch** (`inside_hoopers_hut.back_of_hut_2`, `slam_door_shut_and_gone.time_to_move_now` — *not* covered). Two consequent gaps surfaced, both fixable inside `Compiler/`: (1) the expression parser rejected dotted identifiers (`InkParserExpressions.isIdentifier`), so `{a.b: …}` failed at parse time before lowering — ADR-011 item 1 covered choice `(label)`/`{condition}` parsing only; (2) knot/stitch absolute paths were never registered nor CountVisits-flagged — ADR-011 items 4/5 addressed labelled weave containers only.

The user approved expanding steps 02-03 and 03-01 to deliver the full subsystem rather than ship a partial one. The design was **generalised from "weave label" to "any read-count-referenced named container"** — resolving dotted references against the weave-label table AND the existing knot/stitch `namedContent` absolute paths (the same paths diverts already target — single source of path truth), and flagging exactly the referenced knots/stitches alongside labelled containers. No new component, zero CREATE NEW; ADR-011's governing principles (reuse cached paths, never re-derive; flag only referenced targets) were preserved and merely generalised. This back-propagation is recorded in ADR-011's Status note (AMENDED 2026-06-15) and the `## Wave: DELIVER / [WHY] Upstream Issues` section of `feature-delta.md` (the four-dotted-ref evidence table).

The RED-pin AT was honoured as authored: it uses `waiting.guard_post` (knot.**stitch**) — exactly the needed-but-unscoped shape, not a fixture/mechanism mismatch.

### FOLLOW-UP — TheIntercept e2e remains descoped (precise remaining blocker)

> **This is a clearly-flagged FOLLOW-UP, not a regression and not delivered work.**

The flagship **TheIntercept e2e** (`The Intercept compiles natively and plays identical to the inklecate oracle`) remains `.disabled` with an evidence-backed reason. This slice delivered the read-count addressing subsystem that ADR-011 had hoped would close the e2e — but closing the e2e was discovered to require a **THIRD subsystem beyond ADR-011**: variable-text `{|…|}` at a **gather-lead position** threading back into the gather's nested choices (a `VariableTextEmitter` + gather-lead continuation-threading concern), with further unknown blockers past line 86 of `TheIntercept.ink`.

Per the user (2026-06-15: "cut losses; find an alternative approach"), this is a **multi-subsystem follow-up to be designed afresh — an alternative closure strategy, not chased per-blocker**. The "zero `.disabled` ATs at finalize" invariant is **consciously WAIVED for this one e2e AT** (carried forward from `compiler-variable-text` slice-04, now with a precise, evidence-backed reason and a delivered subsystem behind it). Context: ADR-011 (AMENDED) and `feature-delta.md`'s Upstream-Issues section.

### Cross-Feature Signal / Lesson

**A deep integration test surfaces latent subsystems one layer at a time — budget for that, don't chase it blocker-by-blocker.** TheIntercept's full native-compile e2e has now falsified two successive "this is the last blocker" premises: `compiler-variable-text` slice-04 falsified "line 86 variable text is the sole blocker" (surfacing the `not` operator + this weave-label subsystem); this slice in turn revealed a third subsystem (variable-text-at-gather-lead). Each honest RED was correct and valuable — but the pattern is that a single flagship end-to-end fixture is a *discovery instrument*, not a closeable checklist item. The lesson: when a deep e2e keeps unmasking unrelated subsystems, stop incremental blocker-chasing and **design a deliberate, scoped closure strategy** for the remaining surface as its own piece of work (the user's "alternative approach" decision). The per-slice subsystems (variable-text lowering, read-count addressing) were each correct, oracle-green, and independently valuable; bundling them under one e2e's GREEN was the false economy.

### Components EXTENDed (no new components — all EXTEND, per ADR-011)

| Component | Path | Extension this slice |
|---|---|---|
| `InkParser` / `InkParserExpressions` | `Compiler/Parser/` | Choice `(label)` + `{condition}` parsing; dotted-identifier acceptance in expressions; two surgical parser fixes (gather `- -> target` mis-level; `text[]suffix` empty-bracket split) |
| `CompilerAST` | `Compiler/AST/` | `choice` case gains `weaveLabel: String?` + `condition: InkExpression?` |
| `WeaveEmitter` | `Compiler/Codegen/` | Label-keyed choice containers; `0x1` CountVisits flag on read-count-referenced targets only; labelled label→absolute-path + knot/stitch path discovery |
| `RuntimeObjectEmitter` / `LoweringContext` | `Compiler/Codegen/` | `weaveLabelPaths` table; discovery pre-pass; `.readCount(resolvedPath)` emission in `lowerExpression` (miss → fall through to `.variableReference`) |

### Source-of-Truth Pointers (this milestone)

| Artifact | Path |
|---|---|
| ADR (Option B, AMENDED 2026-06-15) | `docs/product/architecture/adr-011-weave-label-read-count-addressing.md` |
| Feature delta (DESIGN + DELIVER Upstream-Issues) | `docs/feature/native-ink-compiler/feature-delta.md` |
| Architecture brief (Component Inventory) | `docs/product/architecture/brief.md` |
| KPI contracts (kpi-1 ceiling note) | `docs/product/kpi-contracts.yaml` |
| Compiler sources | `Sources/SwiftInkRuntime/Compiler/` |

---

## Milestone — Native↔inklecate Emission Alignment / TheIntercept e2e Closed

**Date**: 2026-06-16
**Milestone scope**: close the full-story native-compile execution-equivalence gap for the flagship `TheIntercept.ink` — the north-star ceiling fixture that survived as the project's one consciously-`.disabled` AT across `compiler-variable-text` and the weave-label slice. Implements **ADR-012 (Track A behavioral fixes; Track B cosmetic assertions)**, now **DELIVERED**.
**Commits**: `4686262..5d3b27e` on `main` (15 probe-driven steps 01-01..01-15 — trunk-based, committed step-by-step as each went green)
**Test result**: native `TheIntercept.ink` plays **80/80** oracle lines line-for-line / choice-for-choice; the full-compile e2e is **re-enabled and GREEN**; full suite **334 tests GREEN**; **0 `.disabled` ATs remain** (finalize invariant met)
**Quality gates**: SwiftLint `--strict` boundary rules R1/R3/R5 held throughout (`Compiler/` only; runtime REUSE-AS-IS); DES integrity **15/15 steps complete RED/GREEN/COMMIT traces (exit 0)**; mutation testing disabled project-wide (CLAUDE.md)

### Milestone Summary

The flagship goal is **ACHIEVED**: `TheIntercept.ink` compiles natively and plays identical to the inklecate oracle for all 80 lines along the fixed choice script. The behavioral root causes ADR-012 enumerated are all closed by **general** compiler fixes (~17 distinct parity hardenings, not story patches): **#3b** variable-text / weave continuation threading, **#4a** implicit read-count coverage, and **#4b** nested choice-label read-counts (flat-namespace resolution of labels nested at any depth). The cosmetic divergence classes — **#1** conditional naming, **#2** flag breadth, **#3a** anonymous nesting — remained **D5-licensed** (untouched, confirmed harmless by the green e2e).

The 15-step climb, with the achieved oracle-matching floor after each:

| Step | Commit | Fix | floor |
|---|---|---|---|
| 01-01 | `4686262` | opts-gather loose-end stitch-local divert qualification | 4 → 6 |
| 01-02 | `64aa56f` | deep nested-label read-count (folded labels under flat knot-namespace) | 6 → 11 |
| 01-03 | `4d25dbf` | pushes_cup path: deeper-gather parse, sibling-body ordinal, weave-label divert, mid-line divert/glue | 11 → 15 |
| 01-04 | `e674fa5` | inline-conditional fall-through + bare-label read-count + weave-in-continuation | 15 → 16 |
| 01-05 | `89e532c` | gather-opened block conditional + leading glue (parser) | 16 → 17 |
| 01-06 | `5f4fc4f` | block-conditional fall-through into rejoin + read-count path reconciliation | 17 → 19 |
| 01-07 | `58e908b` | tunnel chain `-> A -> B` | 19 → 22 |
| 01-08 | `ae4eb6b` | bare `->->` tunnel-return recognition | 22 → 29 |
| 01-09 | `72706bc` | block-conditional-opened guarded menu (rejoin weave-routing + guards) | 29 → 40 |
| 01-10 | `8105738` | leading-glue line-join in inlineBodyStatements | 40 → 55 |
| 01-11 | `5356f26` | bare read-count local-knot scope + gather-conditional-then-choices routing | 55 → 63 |
| 01-12 | `2fbc378` | guarded-if/else vs switch discriminator (opensWithArm) | 63 → 73 |
| 01-13 | `78a4e38` | forceful inline conditional (BodyLowering sub-container nesting) | 73 → 76 |
| 01-14 | `fdfa78f` | post-block leading-glue verbatim (preserve inter-fragment space) | 76 → **80** |
| 01-15 | `5d3b27e` | re-enable the TheIntercept e2e (capstone; discharges the waived `.disabled` exception) | 80 |

### Probe-Driven Methodology + Acceleration Data

The gate was the **DIAG_INTERCEPT2 real-story playback probe** with a **ratchet AT** pinning the matched-line floor, only ever rising. Per-increment line-yield was non-monotonic but ultimately accelerating: batch 1 ~+3.7/inc (opening structural blockers) → batch 2 ~+1.3/inc (the construct-dense interrogation scene) → batch 3+ accelerating to **+15** in a single increment (01-10) once distinct-construct debt was paid and large linear sections opened. This confirmed yield rises as construct debt is paid — refuting the infinite-whack-a-mole worry that earlier slices had raised.

### The General-Parity Lesson

Every one of the ~17 fixes was a **general** compiler defect repair (scoping, keying, divert qualification, conditional rejoin, read-count path resolution, glue preservation) — real parity hardening, not story-specific patches. The flagship story is a *discovery instrument* that surfaces latent general gaps; fixing them generally (rather than special-casing TheIntercept) is what made the green durable and the suite regression-free.

### Cross-Feature Signal — the playback-probe-as-gate pattern

**Synthetic minimal fixtures false-greened.** Across `compiler-variable-text` and the weave-label slice, granular miniatures passed while TheIntercept stayed dead at line 4 — local greens that did not advance the real e2e. The honest gate turned out to be a **real-story playback probe** (DIAG_INTERCEPT2): drive fixes against actual story complexity and ratchet the matched-line floor upward, one real blocker at a time. **This playback-probe-as-gate pattern is reusable for any compiler/transpiler execution-equivalence work** — when a deep end-to-end fixture keeps unmasking latent subsystems, gate on the real fixture's progress (a monotonic ratchet), not on synthetic proxies that can pass without moving the real target.

### Retained Diagnostic Harnesses (durable regression instruments)

| Harness | Path | Role |
|---|---|---|
| DIAG_INTERCEPT (structural census) | `Tests/SwiftInkRuntimeTests/Diagnostics/TheInterceptDivergenceDiagnostic.swift` | structural tree-diff census (cosmetic-vs-behavioral) |
| DIAG_INTERCEPT2 (playback probe) | `Tests/SwiftInkRuntimeTests/Diagnostics/TheInterceptPlaybackProbe.swift` | the honest gate — real-story matched-line probe |
| ratchet progress AT | `Tests/SwiftInkRuntimeTests/Acceptance/Compiler_TheInterceptProgressTests.swift` | pins the achieved oracle-matching floor (now full 80) |

### Source-of-Truth Pointers (this milestone)

| Artifact | Path |
|---|---|
| ADR-012 (DELIVERED) | `docs/product/architecture/adr-012-native-inklecate-emission-alignment.md` |
| Feature delta (DELIVER batches + e2e CLOSED) | `docs/feature/native-compiler-emission-alignment/feature-delta.md` |
| Roadmap (15-step plan) | `docs/feature/native-compiler-emission-alignment/deliver/roadmap.json` |
| Execution log (step history) | `docs/feature/native-compiler-emission-alignment/deliver/execution-log.json` |
| Architecture brief (Feature Coverage Matrix + Component Inventory) | `docs/product/architecture/brief.md` |
| KPI contracts (kpi-1 MET) | `docs/product/kpi-contracts.yaml` |
| Compiler sources | `Sources/SwiftInkRuntime/Compiler/` |
