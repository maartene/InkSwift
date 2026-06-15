# Feature: native-compiler-emission-alignment

Close the execution-equivalence gap between the native Ink compiler and inklecate for full stories
(TheIntercept is the exemplar). DESIGN-only — produces ADR-012 + this brief; no implementation.

Primary evidence: `docs/analysis/theintercept-native-divergence-2026-06-15.md`.
ADR: `docs/product/architecture/adr-012-native-inklecate-emission-alignment.md`.
Instrument: `Tests/SwiftInkRuntimeTests/Diagnostics/TheInterceptDivergenceDiagnostic.swift`.

---

## Wave: DESIGN / [REF] Decisions

| ID | Decision | Verdict | Rationale (file:line) |
|----|----------|---------|------------------------|
| D1 | Correctness target is D5 Level-1 execution-equivalence, NOT structural identity | Locked | `adr-011:80-84`; structural diff is a superset of behavioral diff (`analysis:41`) |
| D2 | Runtime is REUSE-AS-IS; all fixes inside `Compiler/` | Locked | R1/R3/R5 boundary; demand-flag machinery complete (`InkEngine.swift:80,237,919,1043`) |
| D3 | Flagging model is correct & shipping; #2 is NOT a defect | Locked | demand-flag: flag iff read (`InkEngine.swift:80-83`); auto-flag pass (`RuntimeObjectEmitter.swift:74-95`) |
| D4 | Only the read-count-backed subset of the 447 oracle flags is REQUIRED | Locked | `visitCounts` consumed only by `.readCount` (`InkEngine.swift:237-240`); once-only via `ChoiceFlags` (`InkEngine.swift:369,1003`) |
| D5 | Track B (assert equivalence) for #1, #2, #3a; Track A (fix emission) for #3b, #4a, #4b | Locked | per-class triage below |
| D6 | Promote the diagnostic to a permanent behavioral-comparison harness | Locked | feeds granular ATs (`analysis:47`) |
| D7 | Pursue behavioral residue (Phases 1–3); hold the subset-cap as contingency | Locked | residue is bounded; cap only if Phase 3 intractable |

---

## Wave: DESIGN / [REF] Behavioral-vs-cosmetic triage

| Root cause | Census | Behavioral or cosmetic? | Flag-requirement finding |
|---|---|---|---|
| **#1 Conditional shape** (`cond{N}-*` named vs anonymous `nop`-scaffold) | `nop` 1 vs 107 | **COSMETIC** — D5 licenses own shape; both arms rejoin a shared `-end`/`check.5` (`ConditionalEmitter.swift:22-27`) | n/a |
| **#2 Flagging breadth** (7 vs 447) | flagged 7 vs 447 | **COSMETIC / subsumed by #4** | Runtime flags iff visit count is *read* (`InkEngine.swift:80-83,919-921,1043-1046`); count read only by `.readCount` (`:237-240`). Once-only/gather revisit use `ChoiceFlags`, not container flags (`:369-376,1003-1012`; `StoryState.swift:191`). **Required flags ≤ 54 read-count targets, not 447.** ~393 are inklecate-internal. Native already auto-flags exactly the read targets (`RuntimeObjectEmitter.swift:74-95`; `VariableTextEmitter.swift:90,187`). |
| **#3a Anonymous vs named nesting** | container 450 vs 1272 | **COSMETIC** — named absolute-path addressing is a deliberate native choice (`WeaveEmitter.swift:36-40`) | n/a |
| **#3b `opts` gather-lead variable-text dead-end** | line-86 e2e blocker | **BEHAVIORAL** — divert lands in a sequence container that dead-ends instead of threading into the gather's nested choices (`analysis:35`) | none — pure control-flow bug |
| **#4a Implicit read-count coverage** (sequences covered; knot/stitch-visit conditionals, sticky-choice counts) | readCount 8 vs 54 | **BEHAVIORAL** — these drive conditionals/continuation along the script (`analysis:37,41`) | each new read-count auto-flags its target via the existing reconciliation pass (`RuntimeObjectEmitter.swift:74-95`) |
| **#4b 2 unresolved dotted refs + missed flags** (`putmein`, `try_the_door`, `try_the_windows`, `go_to_hoopers_dorm` oracle `0x1`/native `0x0`) | dottedVariableReference 2 vs 0 | **BEHAVIORAL** — unresolved ref evaluates to a runtime-unresolvable variable; missed flag → read-count evaluates 0 (`adr-011:61-63`) | flag the *referenced* target (ADR-011 principle, not yet covering these knots/stitches) |

**Headline finding**: root cause #2 (the scariest census number, 7 vs 447) is **not a defect**. The
447↔7 gap is licensed by the demand-flag runtime model — the native compiler only needs to flag the
containers whose counts it reads, and it already does. #2 collapses into #4 (read-count coverage).
The real backlog is **one nesting bug (#3b) + read-count coverage (#4a) + a dotted-ref tail (#4b)**.

---

## Wave: DESIGN / [WHY] Options considered (per behavioral class)

### #3b — `opts` gather-lead variable-text

| Option | Trade-off | Verdict |
|---|---|---|
| (a) Align to inklecate: emit anonymous nested choice containers under the gather | Matches oracle nesting; large `WeaveResolver` rewrite; reintroduces relative addressing | Rejected — high risk, D5 makes shape free |
| (b) Keep named shape; fix the `WeaveResolver`↔`VariableTextEmitter` splice so a gather leading with `.variableText` threads its `-end` continuation back into the gather's `nested` choices | Localized to the splice; preserves named addressing; proven by a granular AT before the e2e | **CHOSEN** |

### #4a — implicit read-count coverage

| Option | Trade-off | Verdict |
|---|---|---|
| (a) Flag every container (inklecate `countAllVisits`-style) | Trivial; bloats `visitCounts`; diverges from committed oracle which has `countAllVisits` OFF (`adr-011:124-128`) | Rejected |
| (b) Extend the discovery pre-pass to recognize knot/stitch-visit conditional subjects + sticky-choice visit references → emit `.readCount` → auto-flag target via existing reconciliation | Reuses shipping machinery; demand-flag stays exact; one coverage addition per shape | **CHOSEN** |

### #4b — dotted-ref residue + missed flags

| Option | Trade-off | Verdict |
|---|---|---|
| (a) Post-emission tree re-walk to rewrite stragglers | Re-derives paths inklecate deliberately avoids (`adr-011:193-207`) | Rejected |
| (b) Extend the ADR-011 label/knot/stitch resolution table to the 4 named targets so resolution hits and the referenced container is flagged | Same reuse-cached-path principle as ADR-011; `dottedVariableReference` → 0 | **CHOSEN** |

### #1/#2/#3a — Track B (assert, do not fix)

| Option | Trade-off | Verdict |
|---|---|---|
| (a) Align emission to oracle shape | Rewrites proven emitters for cosmetic parity; flags ~393 dead containers | Rejected |
| (b) Keep shape; narrow the diagnostic to behavioral fields; document licensed divergences | Smallest diff; preserves emitters + demand-flag model | **CHOSEN** |

---

## Wave: DESIGN / [REF] Component impact map

| Component | File | Change type | What | Phase |
|---|---|---|---|---|
| `WeaveEmitter` / `WeaveResolver` | `Compiler/Codegen/WeaveEmitter.swift` | EXTEND | gather-lead variable-text splice (#3b); extend discovery for sticky/visit read-counts (#4a) | 2,3 |
| `VariableTextEmitter` | `Compiler/Codegen/VariableTextEmitter.swift` | EXTEND | thread `-end` continuation back to gather nested choices (#3b) | 3 |
| `RuntimeObjectEmitter` | `Compiler/Codegen/RuntimeObjectEmitter.swift` | EXTEND | resolve 4 residual dotted refs (#4b); recognize knot/stitch-visit conditional subjects (#4a). Auto-flag pass reused as-is (`:74-95`) | 1,2 |
| `ConditionalEmitter` | `Compiler/Codegen/ConditionalEmitter.swift` | **REUSE-AS-IS** | shape is cosmetic (#1); no change | — |
| `JSONEmitter` | `Compiler/Codegen/JSONEmitter.swift` | REUSE-AS-IS | serialization unaffected | — |
| Diagnostic harness | `Tests/.../Diagnostics/TheInterceptDivergenceDiagnostic.swift` | EXTEND | permanent; add behavioral-field-only comparison + per-construct report | 0,4 |
| Runtime (`Engine`, `Decoder`, `StoryState`) | `Engine/*.swift`, `Decoder/*.swift` | **REUSE-AS-IS** | demand-flag + read-count machinery complete; R1/R3/R5 forbids change | — |

### Reuse Analysis

| Existing Component | File | Overlap | Decision | Justification |
|---|---|---|---|---|
| WeaveResolver | `Compiler/Codegen/WeaveEmitter.swift` | gather/choice nesting, loose-end stitching | EXTEND | #3b is a splice fix in the existing resolver, not a new traversal |
| RuntimeObjectEmitter auto-flag pass | `Compiler/Codegen/RuntimeObjectEmitter.swift:74-95` | flag-on-read-count reconciliation | EXTEND/REUSE | #4a/#4b add `.readCount` emission; flagging is reused unchanged |
| WeaveDiscovery pre-pass | `Compiler/Codegen/WeaveEmitter.swift:139-239` | label-path + referenced-label discovery | EXTEND | #4a adds sticky/visit reference recognition to the existing pass |
| Runtime visit-count machinery | `Engine/InkEngine.swift` | flag-gated visit tracking | REUSE-AS-IS | demand-flag model already correct; R1 forbids `Compiler→Engine` |

Zero CREATE NEW.

---

## Wave: DESIGN / [REF] Granular per-construct equivalence AT plan

Authored in DISTILL as small RED fixtures (each `.disabled` until its DELIVER phase, per CLAUDE.md),
to localize each behavioral gap instead of relying on the monolithic TheIntercept e2e.

| AT fixture | Construct | Pins | Phase |
|---|---|---|---|
| `dotted-readcount-knot-visit` | `{knot_name: …}` / `{not knot.stitch: …}` knot/stitch-visit conditional | resolves to `.readCount`, target flagged, `dottedVariableReference == 0` | 1 |
| `sequence-cycle-once-readcount` | `{a\|b\|c}`, `{&…}`, `{!…}` | already covered — regression pin via diagnostic behavioral fields | 0 |
| `sticky-choice-visit-count` | `+ choice` revisited; `{choice_label: …}` reads its count | sticky choice visit count read correctly | 2 |
| `gather-lead-variable-text` | gather leading with `{a\|b}` then nested choices (`opts` shape) | no dead-end; threads into nested choices; play matches oracle | 3 |
| `conditional-rejoin-equivalence` | block/switch `{c: … - else: …}` | both arms rejoin; play-equivalent despite `cond{N}-*` naming (Track B assertion) | 4 |
| `theintercept-e2e` (re-enable) | full story, choice script `[0,2,1,0,0,1,2,0,1,0]` | native == oracle line-for-line | after 3 |

**Diagnostic harness role**: the permanent comparison instrument. It (1) feeds per-construct
divergence reports that seed the fixtures above, and (2) after Phase 4 compares **behavioral fields
only** (text/newline/divert/choicePoint/readCount sequences + required flags), so licensed cosmetic
divergence (#1/#2/#3a) does not register as drift. It is the regression backstop behind the e2e.

---

## Wave: DESIGN / [REF] Phased roadmap outline

| Phase | Scope | Value/Risk | Gate |
|---|---|---|---|
| 0 | Promote diagnostic to permanent behavioral harness | High value / zero risk | per-construct report emits |
| 1 | #4b dotted-ref residue + missed flags (4 named targets) | High / low — ADR-011 tail | `dottedVariableReference == 0`; 4 targets flagged |
| 2 | #4a implicit read-count coverage (knot/stitch-visit, sticky) | High / medium | readCount coverage AT green |
| 3 | #3b `opts` gather-lead variable-text | High / **high** | gather-lead AT green; e2e past line 86 |
| 4 | Track B equivalence assertions for #1/#2/#3a | Medium / low | diagnostic behavioral-field comparison; document licensed divergences |

Constraint: every phase inside `Compiler/`; runtime REUSE-AS-IS (R1/R3/R5). Trunk-based per-step
commits; each phase re-enables only its own `.disabled` AT on green (CLAUDE.md).

---

## Wave: DESIGN / [WHY] Strategic recommendation

**Pursue full execution-equivalence for the behavioral residue (Phases 1–3); do NOT cap to a subset
now.** Reasoning grounded in the census:

- The frightening magnitude (native ≈ ⅓ of oracle; flags 7 vs 447) is almost entirely **structural**,
  which D5 explicitly licenses away. Once the demand-flag finding (D3/D4) removes #2 from the backlog,
  what remains is a **bounded, enumerable behavioral set**: one nesting bug (#3b), read-count coverage
  (#4a), and a 4-target dotted-ref tail (#4b) — not a multi-quarter rewrite.
- TheIntercept is the project's existing flagship gate; the diagnostic now localizes every remaining
  gap, so the work is per-construct ATs, not e2e archaeology.
- **Contingency**: if Phase 3 (`opts` gather-lead) proves structurally intractable in `WeaveResolver`,
  fall back to the documented-subset cap (route TheIntercept-class stories to inklecate, keep native
  at its passing supported ceiling). Adopt the cap only on that evidence — it is the explicit
  fallback, not the default.

---

## Wave: DESIGN / [REF] Open questions (deferred to DISTILL/DELIVER)

- Exact enumeration of #4a implicit read-count shapes beyond knot/stitch-visit + sticky (long tail
  surfaced during Phase 2) — DISTILL to derive from the diagnostic's per-construct report.
- Whether the `opts` fix (#3b) requires any `VariableTextEmitter` stage-container `-end` signature
  change vs a pure `WeaveResolver` splice — DELIVER Phase 3 RED to localize.
- Phase 4 behavioral-field set: confirm `flags` comparison restricts to read-count-backed flags only.

---

## Wave: SPIKE / [REF] Phase-3 feasibility (#3b gather-lead variable-text) — 2026-06-15

**Verdict: TRACTABLE (with caveats).** The fix is **entirely inside `Compiler/`, no runtime/Engine/Decoder change** (boundary clean; every mechanism — conditional diverts, choicePoints, `seq*-d`/`seq*-end` containers, visit-count dispatch — already exists; only two divert *targets* change). The Option-C subset-cap fallback is therefore **not needed** for Phase 3.

**Key discovery — the bug is TWO layers, and layer 2 is broader than #3b:**
1. **Threading (the #3b headline).** A gather whose lead line is a variable-text `{|…|}` must make the gather's nested choices the *continuation* (`seq*-end`) of that line, instead of orphaned siblings emitted after the dispatch divert (today they are unreachable → total dead-end, native play `[]`).
2. **Loose-end propagation (PRE-EXISTING latent bug, orthogonal to gather-lead).** `RuntimeObjectEmitter.continuationLowerer` (~line 743) calls `WeaveEmitter.lower` with a hardcoded `fallThrough: .end` (`WeaveEmitter.swift:90`), so choices that follow ANY variable-text line and then gather get the wrong fall-through target. This already mis-compiles the **inline** variable-text path (not just gather-lead), and is exactly why the real `opts`/`waited` exemplar (`* [Wait]` empty body → `- -> waited`, TheIntercept lines 105-106) fails. Both layers must be fixed together — the naive layer-1 fix converges onto layer-2's residual bug.

**Recommended fix shape (probe-validated, 324/324 existing tests green on the layer-1 fold):**
- Plumb an enclosing `fallThrough` target down `lowerBody → lowerVariableTextLine → continuationLowerer → WeaveEmitter.lower` (replace the hardcoded `.end` at `WeaveEmitter.swift:90`; `WeaveResolver.FallThrough` already models `.gather([String])`/`.end`).
- Gather-lead threading: **Option (A) parser fold** (keep the gather's nested choices in the flat `body` when the lead is variable-text/inline-conditional, so the flat path threads them) — smallest diff, zero observed regression. Option (B) resolver splice in `WeaveResolver.containerSpliced` is more faithful to inklecate's inlined shape but touches the shared named-collector flow.

**Regression surface:** low — no current passing fixture exercises "variable-text line precedes choices that gather" (which is why layer 2 went unnoticed), so the layer-2 plumbing must be guarded by NEW ATs.

### DISTILL tuning (granular ATs to author — execution-equivalence via `compileAndPlay`, not structural)

| Fixture | Source shape | Pins |
|---|---|---|
| `gather-lead-vt-end` | gather lead `{\|x\|}` + 2 choices + `-> END` | layer 1 (threading); loose-end = `end` |
| `gather-lead-vt-gather` | gather lead `{\|x\|}` + 2 choices + trailing `- They wait.` | **layer 2** (loose-end → enclosing gather) — discriminating case |
| `inline-vt-choices-gather` | knot-lead inline `{\|x\|}` + 2 choices + trailing gather | the **pre-existing inline** latent bug, independent of gather-lead |
| `gather-lead-vt-empty-choice` | gather lead `{\|x\|}` + `* [Wait]` empty-body choice + trailing gather | the exact TheIntercept `opts`/`waited` exemplar in miniature |
| `gather-lead-cycle-vs-once` | as `-end` but `{&a\|b}` and `{\!a\|b}` | threading is mode-independent (seq/cycle/once) |
| `gather-lead-vt-single-choice` | gather lead `{\|x\|}` + exactly 1 choice | boundary: single vs multi nested choice |

Then re-enable `theintercept-e2e` after these land (its lines 85-106 are `gather-lead-vt-empty-choice` + an explicit `-> opts` loop-back). **DISTILL must add a #3b-layer-2 phase note:** the loose-end fix is a pre-existing-bug repair, so the `inline-vt-choices-gather` AT belongs to the same DELIVER step even though it is not gather-lead.
