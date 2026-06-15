# ADR-012: Native compiler ↔ inklecate emission alignment for execution-equivalence

## Status

**Proposed** (DESIGN — native-compiler-emission-alignment feature, 2026-06-15).
Supersedes the *scope* of ADR-011 (weave-label read-count addressing): ADR-011 solved one
read-count shape (named-weave-label); this ADR reframes the whole native ↔ inklecate gap and
decides, per divergence class, whether to align emission shape or assert execution-equivalence.

Primary evidence: `docs/analysis/theintercept-native-divergence-2026-06-15.md` (structural
tree-diff census + four systemic root causes). Instrument:
`Tests/SwiftInkRuntimeTests/Diagnostics/TheInterceptDivergenceDiagnostic.swift`.

## Context

The native Ink compiler (`Sources/SwiftInkRuntime/Compiler/`) emits a `ContainerNode` tree that
the runtime plays. The flagship `TheIntercept.ink` story diverges from the inklecate oracle: the
play-equivalence e2e dead-ends at line ~86 of ~1600. The divergence diagnostic compared the
*whole* trees and found the native tree is ≈⅓ the size of inklecate's, clustering into four
systemic root causes:

| # | Root cause | Census signal |
|---|---|---|
| 1 | Conditional emission shape (`cond0-b0/b1/else/end` vs anonymous `nop`-scaffold) | `nop` native=1 vs oracle=107 |
| 2 | Visit-count flagging breadth | flaggedContainers native=7 vs oracle=447 |
| 3 | Weave/sequence/variable-text nesting (`opts` gather-lead dead-end) | line-86 blocker |
| 4 | Read-count breadth + 2 unresolved dotted refs + missed flags | readCount native=8 vs oracle=54 |

**Governing constraint: Correctness is D5 Level-1 execution-equivalence** — native playback ==
committed inklecate oracle *along the fixed choice script* (line-for-line, choice-for-choice). The
compiler is licensed to emit its OWN tree shape; it need NOT reproduce inklecate's container IDs,
nesting depth, or internal scaffolding. Structural divergence is therefore a **superset** of
behavioral divergence — the design's first job is to separate the two.

### Decisive runtime evidence (the flagging question — file:line)

The runtime is **demand-flagged**: a container's visit count is tracked *only* when the container
carries the `#f` bit-0 (`containerFlagCountVisits = 0x1`) flag, and that count is *only ever
consumed* by a `.readCount` node.

- `InkEngine.enterContainer` increments `visitCounts` iff `flags & 0x1 != 0` — `InkEngine.swift:80-83`
- `InkEngine.applyDivert` (absolute target) — same guard — `InkEngine.swift:919-921`
- `InkEngine.chooseChoice` (choice body) — same guard — `InkEngine.swift:1043-1046`
- `.readCount` is the only reader of `visitCounts` during play — `InkEngine.swift:237-240`
- **Once-only choices do NOT use container flags** — they use `ChoiceFlags.isOnceOnly` +
  `state.chosenChoiceTargets` — `InkEngine.swift:369-376`, `1003-1012`; `StoryState.swift:191`.
- **Gather revisits / sticky choices** ride the same `ChoiceFlags` machinery, not container flags
  — `WeaveEmitter.swift:601-609` (sticky clears `isOnceOnly`).
- The native compiler already implements demand-flagging end-to-end: `VariableTextEmitter` emits
  `#f:5` on the exact dispatch container whose `visit` count it reads (`VariableTextEmitter.swift:90,187`),
  and `RuntimeObjectEmitter` runs a post-emission reconciliation that flags exactly the container
  paths referenced by an emitted `.readCount` (`RuntimeObjectEmitter.swift:74-95, 404-405`).

**Conclusion**: of the 447 oracle flags, our runtime *requires* only the subset whose visit count
is actually read (≤ the 54 read-count targets). The remaining ~393 are inklecate-internal
(inklecate flags many containers it never reads back, or reads via mechanisms our runtime models
with `ChoiceFlags`). **The flagging *model* is correct and already shipping; the gap is read-count
*coverage*, not the flag count.** This collapses root cause #2 into root cause #4.

## Decision

Adopt a **two-track, per-class strategy**: keep the native compiler's own tree shape and *assert*
execution-equivalence (Track B) for cosmetic divergences; *fix emission* (Track A) only where the
divergence is behaviorally observable along a choice script. All work stays inside `Compiler/`;
the runtime is REUSE-AS-IS (no `Engine/`, `Decoder/`, `StoryState` change).

### Per-class decision

| Class | Verdict | Track | Decision |
|---|---|---|---|
| #1 Conditional shape | **Cosmetic** | B | Keep `cond{N}-*` named shape; assert equivalence via granular conditional ATs. No alignment to inklecate's anonymous `nop`-scaffold. |
| #2 Flagging breadth | **Cosmetic (subsumed by #4)** | B | Keep demand-flag model. The 447↔7 gap is not a defect; only read-count-backed flags are required and they already auto-emit. |
| #3a Anonymous-vs-named nesting | **Cosmetic** | B | Keep named `c-N`/`g-N`/`seq{N}` nesting; do not deepen to match oracle anonymous nesting. |
| #3b `opts` gather-lead variable-text dead-end | **BEHAVIORAL** | A | Fix `WeaveResolver`/`VariableTextEmitter` interaction so a gather that leads with variable-text threads back into the gather's nested choices instead of dead-ending. |
| #4a Implicit read-counts (sequences `{\|…\|}` already covered; knot/stitch-visit conditionals, sticky-choice visit counts) | **BEHAVIORAL** | A | Extend read-count *emission coverage* so knot/stitch-visit conditionals and sticky-choice visit references lower to `.readCount` + auto-flag. |
| #4b 2 unresolved dotted refs + missed flags on `putmein`/`try_the_door`/`try_the_windows`/`go_to_hoopers_dorm` | **BEHAVIORAL** | A | Close the dotted-reference resolution + flag-on-referenced-target gap (the residue ADR-011 did not cover). |

### Phased plan (value/risk ordered, all inside `Compiler/`)

1. **Phase 0 — Promote the diagnostic to a permanent instrument** (zero behavioral risk). Make
   `TheInterceptDivergenceDiagnostic` a maintained, behavioral-only comparison harness that emits
   a per-construct divergence report feeding the granular ATs. (See brief.)
2. **Phase 1 — #4b dotted-ref + missed-flag residue** (highest value/lowest risk: it's the
   documented ADR-011 tail; `dottedVariableReference` must reach 0). Fix resolution + flag the
   referenced knots/stitches.
3. **Phase 2 — #4a implicit read-count coverage** (knot/stitch-visit conditionals, sticky-choice
   counts). Reuse the existing discovery-pass + auto-flag reconciliation.
4. **Phase 3 — #3b `opts` gather-lead variable-text** (the line-86 e2e unblocker; highest
   structural risk — touches `WeaveResolver`↔`VariableTextEmitter` splice).
5. **Phase 4 — Equivalence assertions for #1/#2/#3a** (Track B): narrow the diagnostic's
   comparison to behavioral fields and document the licensed cosmetic divergences.

### Strategic recommendation

**Pursue full execution-equivalence — but ONLY for the behavioral residue (Phases 1–3), not
structural identity.** The census magnitude (native ≈ ⅓ of oracle) measures *structural* size,
which D5 licenses away; the *behavioral* residue is a bounded, enumerable set (one nesting bug +
read-count coverage + a dotted-ref tail), not a multi-quarter rewrite. Do **not** cap the native
compiler to a documented subset *yet*: the remaining behavioral work is small and well-localized
by the diagnostic, and TheIntercept is the existing flagship gate. Re-evaluate the cap only if
Phase 3 (`opts`) proves structurally intractable; if so, fall back to the documented-subset cap
(keep inklecate for stories exceeding the supported ceiling) as the explicit contingency.

## Alternatives Considered

### Option A — Align native emission to inklecate's tree shape (rejected, global)

Re-architect `ConditionalEmitter`/`WeaveEmitter` to emit inklecate's anonymous `nop`-scaffolded
conditionals and deep anonymous nesting; flag all 447 containers.

- **Pro**: byte-closer to oracle; the diagnostic's structural diff would shrink toward zero.
- **Con (rejected)**: violates the simplest-solution principle and D5. It would rewrite three
  proven emitters to chase *structural* identity that execution-equivalence does not require,
  flagging ~393 containers the runtime never reads (dead state, `StoryState.visitCounts` bloat),
  and re-introducing fragile anonymous-index addressing the native compiler deliberately replaced
  with named absolute paths (`WeaveEmitter.swift:36-40`). High cost, high regression risk, no
  behavioral benefit. Adopted *only* for the genuinely behavioral sub-classes (#3b, #4a, #4b).

### Option B — Keep native shape, assert execution-equivalence, fix only behavioral residue (CHOSEN)

Per-class triage: Track B (assert + narrow comparison) for cosmetic classes; Track A (targeted
emission fix) for behavioral classes. The diagnostic becomes the permanent equivalence instrument.

- **Pro**: smallest viable diff; preserves three proven emitters and the demand-flag model already
  shipping; honors D5 (shape freedom); localizes work to a bounded behavioral set; every fix is
  guarded by a granular RED AT before the monolithic e2e.
- **Con**: requires disciplined behavioral-vs-cosmetic classification and a maintained diagnostic
  so cosmetic drift is not mistaken for regression. Mitigated by Phase 0 + Phase 4.

### Option C — Cap the native compiler at a documented supported subset (rejected now, held as contingency)

Freeze native at its passing supported-ceiling corpus; route complex stories (TheIntercept-class)
to inklecate permanently.

- **Pro**: zero further compiler risk; honest about the ⅓ structural ratio.
- **Con (rejected now)**: premature — the behavioral residue is small and localized, and TheIntercept
  is the flagship gate the project already committed to. Retained as the **explicit fallback** if
  Phase 3 (`opts` gather-lead) proves structurally intractable.

## Consequences

### Positive

- Reframes a "native is ⅓ of oracle, looks hopeless" census into a bounded behavioral backlog
  (one nesting bug + read-count coverage + a dotted-ref tail).
- Zero runtime/`Engine`/`Decoder`/`StoryState` change — R1/R3/R5 boundary holds; demand-flag model
  reused, not extended.
- Each behavioral fix is localized by a granular per-construct RED AT, not discovered one e2e line
  at a time.
- The diagnostic becomes a permanent regression instrument distinguishing licensed cosmetic
  divergence from real drift.

### Negative / Risks

- **Misclassification risk**: a divergence assumed cosmetic could hide a behavioral bug on an
  unexercised choice path. Mitigation: the granular ATs exercise each construct directly; the
  diagnostic's behavioral-field comparison (Phase 4) backstops the e2e.
- **`opts` (Phase 3) structural risk**: the gather-lead variable-text splice is the deepest
  emitter interaction; it may resist a clean fix. Mitigation: Option C cap is the documented
  contingency.
- **Read-count coverage breadth (Phase 2)**: enumerating every implicit read-count source
  (sequence/once/cycle already covered; knot/stitch-visit conditionals, sticky counts remaining)
  may surface long-tail shapes. Mitigation: discovery-pass + auto-flag reconciliation already
  generalizes (`RuntimeObjectEmitter.swift:74-95`); new shapes are coverage additions, not new
  machinery.

## Architecture Enforcement

Style: Modular monolith — single `Compiler/` layer, ports-and-adapters at the `InkCompiler.compile`
driving port. Language: Swift. Tool: SwiftLint `custom_rules` R1/R3/R5 (already `--strict` in the
pre-commit gate + CI). All phases touch only `Compiler/`; the runtime read-count + flag machinery
is exercised, not extended. Correctness gate: granular per-construct execution-equivalence ATs +
the re-enabled TheIntercept e2e. Mutation testing is disabled project-wide (CLAUDE.md); the
execution-equivalence oracle suite + code review + boundary gates carry test quality.
