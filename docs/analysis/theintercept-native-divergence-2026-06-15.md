# TheIntercept — native compiler ↔ inklecate structural divergence analysis

**Date**: 2026-06-15
**Instrument**: `Tests/SwiftInkRuntimeTests/Diagnostics/TheInterceptDivergenceDiagnostic.swift` (throwaway; compares the native `InkCompiler.compile(TheIntercept).root` tree against `InkDecoder().decode(TheIntercept.ink.json)` — i.e. our compiler's tree vs inklecate's tree, both as `ContainerNode`).
**Why**: the play-equivalence e2e discovered blockers one line at a time (reached line 86 of ~1600). This compares the whole trees at compile time to enumerate the *complete* gap.

## Confidence: the drift is the COMPILER, not the runtime
The e2e holds the runtime constant on both sides (same `CompilerOracle.play`, same script). `Milestone5b` independently plays TheIntercept's **inklecate** JSON through the runtime line-for-line green — so the runtime plays this story correctly. Therefore `native ≠ oracle` is attributable to the native compiler's emitted tree differing from inklecate's. This diagnostic confirms it structurally.

## Global census (naming-invariant)

| Metric | native | oracle | ratio |
|---|---:|---:|---:|
| containers | 450 | 1272 | 0.35 |
| flaggedContainers (flags≠0) | 7 | 447 | 0.02 |
| text | 781 | 1429 | 0.55 |
| newline | 503 | 1241 | 0.41 |
| divert | 487 | 987 | 0.49 |
| choicePoint | 178 | 423 | 0.42 |
| readCount | 8 | 54 | 0.15 |
| dottedVariableReference | **2** | **0** | (should be 0 — unresolved) |
| nativeFunction | 60 | 134 | 0.45 |
| variableAssignment | 66 | 161 | 0.41 |

Control-command histogram standouts: `nop` native=1 vs oracle=**107**; `done` native=26 vs oracle=3; `ev`/`/ev` and `str`/`/str` ~half.

**Headline**: the native tree is ~⅓ of inklecate's, with the biggest relative gaps in **flagging (2%)** and **read counts (15%)**.

## Root-cause clustering (the ~50 named-content findings collapse to ~4 systemic causes)

1. **Conditional emission shape.** Almost every knot/stitch shows native names `cond0-b0/b1/else/end` containers that the oracle does **not** have. inklecate emits conditionals as a different (largely anonymous, `nop`-scaffolded) structure — which also explains the `nop` 1-vs-107 gap and a large share of the container-count deficit. This is one strategy difference repeated story-wide, not dozens of bugs.

2. **Visit-count flagging model is far broader in the oracle (447 vs 7).** ADR-011 assumed "flag only read-count-referenced targets." The oracle flags ~35% of all containers. Much of this is likely once-only-choice / gather visit tracking that our runtime may handle via `ChoiceFlags` rather than container flags (so not all 447 are necessarily *required* under execution-equivalence) — but the gap is systemic and the ADR's flagging model is empirically too narrow. **Needs design, not a patch.**

3. **Weave/sequence/variable-text nesting strategy.** Native names labels (`optimism`, `pessimism`, `devil`, `paused`, `monastic`, `tell_me_now`, `opts`, `outer_zip`, `wide_circuit`…) and flattens; the oracle nests deeper with anonymous containers. The specific `slam_door_shut_and_gone.from_outside_heard → opts` case is the **variable-text-at-gather-lead** blocker the playthrough hit at line 86 (native emits a divert to a sequence container that dead-ends instead of threading back into the gather's nested choices).

4. **Read-count breadth + 2 residual unresolved dotted refs.** Native emits 8 read counts; the oracle 54. ADR-011's *named-weave-label* dotted read-count (its entire focus) is only ~2–4 of those 54 — the bulk are **implicit** read/visit counts from sequences `{|…|}`, knot/stitch-visit conditionals, and sticky choices, which the native compiler largely doesn't emit. Also `dottedVariableReference` native=2 → two dotted refs still fall through unresolved (addressing miss) plus several missed flags on referenced targets (`putmein`, `try_the_door`, `try_the_windows`, `go_to_hoopers_dorm` all show oracle flag `0x1`, native `0x0`).

## Interpretation

- **Structural divergence is a superset of behavioral divergence.** Execution-equivalence (D5) licenses the compiler to emit its own shapes, so causes #1 (cond naming) and parts of #3 (anonymous vs named nesting) may be *semantically equivalent* and harmless. But causes #2 (flagging), #4 (read-count breadth + unresolved dotted refs + missed flags), and the #3 `opts` gather-lead dead-end **are behaviorally meaningful** (they drive conditionals, once-only choices, and continuation).
- **The remaining work is design-level, not a handful of bugs.** The native compiler implements conditionals, visit-flagging, sequences/variable-text, and read-counts with **different strategies** than inklecate. ADR-011 solved a niche (named-weave-label read-counts); the broad picture is systemic.
- **Honest cost signal.** Closing TheIntercept to execution-equivalence is plausibly a multi-design-wave effort touching `ConditionalEmitter`, the flagging model, `VariableTextEmitter`/weave nesting, and read-count emission breadth. It is *not* "a little more DELIVER."

## Recommended next step

A focused **DESIGN wave** ("native compiler ↔ inklecate emission-strategy alignment for execution-equivalence"), with this diagnostic as primary evidence, that decides **per divergence class**: (a) align native emission to inklecate's shape, or (b) prove our shape is execution-equivalent and narrow the oracle comparison accordingly. That design then seeds **granular per-construct equivalence ATs** (conditional, sequence, sticky-choice, gather-lead variable-text, read-count breadth) before any further DELIVER. Promote this diagnostic from throwaway to a permanent comparison harness that generates those granular ATs.

Strategic alternative worth weighing: keep inklecate for complex stories and scope the native compiler to a documented supported subset (it already passes its supported-ceiling corpus) — i.e. accept that full-story execution-equivalence with inklecate may not be worth the cost.
