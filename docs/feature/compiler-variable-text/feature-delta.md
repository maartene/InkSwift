<!-- markdownlint-disable MD024 -->
# Feature Delta: compiler-variable-text (DISCUSS wave)

**Feature**: compiler-variable-text
**Wave**: DISCUSS
**Analyst**: Luna (nw-product-owner)
**Date**: 2026-06-14
**Persona**: Maarten — Swift app developer embedding Ink stories
**Job**: job-native-compilation (reused — validated in the native-ink-compiler wave; NOT re-run)
**Predecessor**: native-ink-compiler (delivered) — this is a follow-on increment.
**Status**: DISCUSS complete — pending peer review + DoR gate before DESIGN handoff

> Density: lean (Tier-1 [REF] sections). DISCUSS describes intent and behaviour
> only — no API signatures, type names, or access modifiers (DESIGN concerns).

---

## Wave: DISCUSS / [REF] Required Reading Checklist

- ✓ `docs/product/jobs.yaml` — `job-native-compilation` (Maarten) reused; feature contribution added under it.
- ✓ `docs/product/journeys/story-author.yaml` — `native-compilation` journey (active) annotated, not duplicated.
- ✓ `docs/product/personas/maarten.md` — reused as-is.
- ✓ `docs/product/ink-feature-reference.md` — THE authoritative gap description; rows 25-27 currently MUST-REJECT with the documented parity-gap caveat; row 28 (shuffle) genuinely runtime-blocked. Line 86 of TheIntercept named as the concrete blocker.
- ✓ `docs/feature/native-ink-compiler/feature-delta.md` — predecessor DISCUSS narrative; US-06 currently rejects these constructs; structure/quality mirrored here.
- ✓ `docs/feature/native-ink-compiler/spike/findings.md` — visit-count-switch shape + once-only choice-flag learnings; the conditional/switch codegen reused by this feature is proven.
- ✓ `docs/feature/native-ink-compiler/slices/slice-06-unsupported-feature-errors.md` — the current located-reject behaviour for rows 25-28; this feature supersedes it for 25-27 and keeps it for 28.

---

## Wave: DISCUSS / [REF] Job Statement (reused)

This feature traces N:1 to the existing, already-validated **job-native-compilation**
(Maarten). No new JTBD was run.

> When I author an Ink story for my Swift app and need to turn it into something my
> app can play, I want to compile it to a runnable story entirely within my Swift
> toolchain, so I can build and ship without depending on the external inklecate
> binary — and get a clear error the moment I use a feature my runtime cannot play,
> instead of shipping a silently broken story.

**This feature's contribution to the job**: closes the documented compiler↔runtime
parity gap for the three *deterministic* variable-text forms. The runtime already
plays the visit-count switch inklecate lowers these into; the native compiler simply
did not lower them yet. Landing the lowering moves rows 25-27 from MUST-REJECT to
MUST-COMPILE, widening "the supported set Maarten can author within" and re-enabling
the descoped flagship fixture — with **zero runtime changes**. Shuffle (row 28) stays
rejected because it additionally needs RANDOM, a genuine runtime gap independent of
this lowering work.

**Emotional micro-arc** (within the existing journey): from *"the toolchain mostly
works but trips on a construct the runtime can actually play — frustrating and
inconsistent"* to *"the deterministic variable-text forms just compile, and the
flagship story builds end-to-end natively — the parity gap is closed."*

---

## Wave: DISCUSS / [REF] Scope Assessment (Elephant Carpaccio Gate)

This is a **small, brownfield, single-bounded-context** increment: one lowering pass
over three closely-related source forms, each lowering to the **same already-proven
visit-count-switch codegen** (the conditional/switch codegen delivered in
native-ink-compiler S4). No runtime change. No new integration contract (the
runnable-story input shape is unchanged). No new persona or job.

Oversized signals check (all NEGATIVE):
- Stories: **4** (≤10).
- Bounded contexts / modules: **1** (the existing compiler).
- Integration points for a walking skeleton: **N/A — walking skeleton NO** (the
  read→parse→codegen→runtime spine already exists and ships).
- Estimated effort: **~3-4 days** total (≤2 weeks), ~1 day per slice.
- Independent shippable outcomes: each form ships independently, but they form one
  coherent family under one job — no candidate for feature-level split.

**Scope Assessment: PASS — 4 stories, 1 bounded context, estimated 3-4 days.** Sliced
into 4 thin end-to-end carpaccio deliverables (once → sequence → cycle → TheIntercept
e2e). No user-confirmation oversize split required.

---

## Wave: DISCUSS / [REF] Locked Decisions

Predecessor decisions D1-D8 (from native-ink-compiler) carry forward; relevance to
this feature noted. Two new decisions (D-A, D-B) locked by the user (Maarten) for
this increment.

| # | Decision | Relevance to compiler-variable-text |
|---|---|---|
| D1 | Compiler scope == runtime scope. | Directly the point: the runtime *can* play these forms, so the compiler now *should* accept them. Closing the parity gap honours D1. |
| D2 | Unsupported constructs rejected with a clear, located error. | Still applies to **shuffle (row 28)** — kept as a clear located reject (regression-guarded in every slice). |
| D3 | Primary output is an in-process runnable story the runtime consumes directly. | Unchanged — lowered variable-text plays through the same runnable-story path. |
| D4 | JSON output is secondary (oracle structural compare + caching). | Unchanged — applies to the lowered output too. |
| D5 | Correctness judged by execution-equivalence against the inklecate oracle. | The correctness gate for every story here — now via the **hermetic oracle** (committed `.ink.json` played through the pure-Swift `Story`, no JS bridge). |
| D6 | Compiler performs compile-time obligations the runtime assumes inklecate did. | The visit-count-switch lowering IS such an obligation — the runtime assumes inklecate already lowered the variable-text source form. |
| D7 | A supported/unsupported feature reference is a first-class deliverable. | Triggers the **downstream doc-update** (rows 25-27 reclassified MUST-COMPILE) — due in DELIVER, recorded below. |
| D8 | The frozen InkSwift (JS-bridge) module is untouched. | Honoured — no runtime, no JS-bridge changes anywhere in this feature. |
| **D-A** | **Scope = rows 25 (sequence), 26 (cycle), 27 (once-only). Shuffle (28) excluded, stays MUST-REJECT.** | User directive. Shuffle additionally needs RANDOM — a genuine runtime gap, out of scope for lowering. |
| **D-B** | **NEW feature `compiler-variable-text`, a follow-on increment to delivered native-ink-compiler, tracing to existing job-native-compilation (Maarten). Reuse job + persona — do NOT create new ones.** | User directive. SSOT updated by adding a feature contribution under the existing job, and annotating (not duplicating) the existing journey. |

---

## Wave: DISCUSS / [REF] Supported vs Unsupported Scope Delta (this feature)

**Moves from MUST-REJECT → MUST-COMPILE** (after this feature lands; doc update due in DELIVER):

| Row | Construct | Lowering rule | Example |
|---|---|---|---|
| 25 | Variable text: sequence `{a\|b\|c}` | Read-count switch, advance through N stages, **clamp** at last stage. | `{red\|green\|blue}` |
| 26 | Variable text: cycle `{&a\|b}` | Read-count switch, advance through N stages, **wrap** via modulo over stage count. | `{&heads\|tails}` |
| 27 | Variable text: once-only `{!a\|b}` / `{\|x\|}` | Read-count switch, first stage then **stop at the last (often empty) stage**. | `{!first time\|}` |

**Stays MUST-REJECT** (regression-guarded in every slice):

| Row | Construct | Why it stays rejected |
|---|---|---|
| 28 | Variable text: shuffle `{~a\|b}` | Additionally requires RANDOM — a genuine runtime gap independent of lowering. Keeps the existing US-06-style located-reject. |

The lowering target shape is the read-count-driven visit-count switch
(`read-count + MIN + ==` + conditional diverts) that the `SwiftInkRuntime` engine
**already executes** — confirmed proven in the predecessor spike findings. The three
forms differ only in the switch's terminal-stage rule: clamp (sequence), wrap (cycle),
stop-at-last (once). This is the one shared artifact of this feature (see registry note).

---

## Wave: DISCUSS / [REF] Journey (lightweight annotation)

The active `native-compilation` journey (Maarten) is **extended, not duplicated**, with
a new path: *author uses a sequence / cycle / once-only form → it compiles in-process →
the runnable story plays the form oracle-identically (advance/wrap/clamp as appropriate)*.

**Shared artifact** (single source): the **visit-count-switch blueprint shape** — the
lowered target all three forms compile into. Its single source of truth is the
compiler's lowering/codegen pass (the existing conditional/switch codegen, extended by
this feature). No second producer of this shape exists; the runtime only *consumes* it.
This is the one integration checkpoint: the lowered switch must match the shape the
runtime already executes (validated by the execution-equivalence oracle).

---

## Wave: DISCUSS / [REF] User Stories

Stories trace N:1 to **job-native-compilation** (`job_id: job-native-compilation`).
Each maps to a slice brief in `slices/`. Per the project DISCUSS-scope rule, the
"After" line of each Elevator Pitch names a conceptual user-invocable entry point
("compile a .ink using {…} … get back a runnable story that plays the oracle-identical
form"), not a Swift signature; the "sees" is concrete observable playback output.

---

### US-01: Compile and play a once-only variable-text form (`{!a|b}` / `{|x|}`)

`job_id: job-native-compilation`

#### Elevator Pitch
- **Before**: Maarten's once-only line `{|I rattle my fingers on the field table.|}`
  is rejected by the native compiler with a located error, even though the runtime can
  play the visit-count switch it lowers into — so the story can't build natively.
- **After**: Maarten compiles a `.ink` using `{!first time|}` (or the bare `{|once|}`)
  and gets back a runnable story that plays the first-time text exactly once, then
  falls silent — line-for-line identical to the inklecate oracle.
- **Decision enabled**: he can keep once-only lines in his story and still drop
  inklecate, because the pure-Swift path now plays them the same way.

#### Problem
Maarten is a Swift app developer who has already moved his whole Ink pipeline to pure
Swift — except his story uses a once-only variable-text line (the exact construct on
line 86 of his flagship fixture). He finds it frustrating that the native compiler
rejects a construct the runtime can demonstrably play, forcing him back to inklecate
for that one story.

#### Who
- Swift app/game developer | owns his build toolchain | has once-only narrative lines | wants the whole pipeline pure-Swift.

#### Solution
Lower the once-only variable-text form (`{!a|b}` and the bare `{|x|}`) into the
read-count-driven visit-count switch the runtime already executes (first stage, then
stop at the last/empty stage); compile and play oracle-identically.

#### Domain Examples
1. **Happy path** — `{!The lock clicks open.|}` behind a sticky choice: selecting the
   choice three times emits the line once, then nothing; identical to the oracle.
2. **TheIntercept line** — `{|I rattle my fingers on the field table.|}` (the literal
   line-86 construct) compiles and plays once, matching the oracle.
3. **Both spellings agree** — `{|The corridor falls quiet.|}` (bare form) lowers to the
   same stop-at-last shape as the `!` spelling and plays identically to the oracle.

#### UAT Scenarios (BDD)
```gherkin
Scenario: A once-only form plays its text exactly once, matching the oracle
  Given a .ink source with "{!The lock clicks open.|}" behind a sticky choice
  When Maarten compiles it in-process and selects the sticky choice three times
  Then "The lock clicks open." is emitted on the first selection only
  And the emitted output across all three selections is identical to the inklecate oracle

Scenario: The bare once-only spelling lowers identically to the "!" spelling
  Given a .ink source using the bare "{|once|}" once-only spelling
  When the source is compiled and played past its first and second visits
  Then the playback is identical to the inklecate-compiled equivalent

Scenario: Shuffle is still rejected with a located error (regression guard)
  Given a .ink source using a shuffle "{~a|b}"
  When the source is compiled
  Then compilation stops with a located error naming "variable-text shuffle" as unsupported
```

#### Acceptance Criteria
- [ ] A once-only form (`{!a|b}` and bare `{|x|}`) compiles in-process to a runnable story.
- [ ] On replay, the first-stage text is emitted exactly once, then the last/empty stage thereafter.
- [ ] Playback is line-for-line identical to the inklecate oracle (execution-equivalence).
- [ ] Shuffle `{~a|b}` still rejects with a named, located error; no story produced.

#### Outcome KPIs
- **Who**: a developer with a once-only variable-text line.
- **Does what**: compiles and plays it natively, oracle-identically.
- **By how much**: 100% of once-only fixtures play line-for-line identical to the oracle; row 28 still rejects (0% silent acceptance).
- **Measured by**: execution-equivalence oracle test over a once-only corpus + a shuffle-reject assertion.
- **Baseline**: today the native compiler rejects every once-only form (0% compile).

#### Technical Notes
- Depends on native-ink-compiler (delivered): reuses the existing visit-count-switch codegen; no runtime change.
- Constraint: do not modify the frozen InkSwift module (D8). Open DESIGN question: where the lowering sits in the pipeline.

---

### US-02: Compile and play a sequence variable-text form (`{a|b|c}`)

`job_id: job-native-compilation`

#### Elevator Pitch
- **Before**: Maarten's ambient sequence line `{red|green|blue}` is rejected natively,
  even though the runtime can play the switch it lowers into.
- **After**: Maarten compiles a `.ink` using `{a|b|c}` and gets back a runnable story
  that emits `a`, then `b`, then `c` and stays on `c` thereafter — line-for-line
  identical to the inklecate oracle.
- **Decision enabled**: he can write N-stage sequences and ship them without inklecate.

#### Problem
Maarten uses sequences for ambient and progressing description (the most common
variable-text form). He needs the general N-stage stop-at-last form to compile
natively so these lines stop forcing him back to the external compiler.

#### Who
- Swift app/game developer | authoring ambient/progressing description | relies on N-stage sequences.

#### Solution
Lower the sequence form `{a|b|c}` (N stages, advance per visit, clamp at the last)
into the read-count-driven visit-count switch; compile and play oracle-identically.

#### Domain Examples
1. **Happy path** — `{red|green|blue}` behind a sticky choice, selected four times,
   emits red, green, blue, blue; identical to the oracle.
2. **Prose stages** — `{First.|Second.|Third and onwards.}` advances then clamps on the
   final stage, matching the oracle.
3. **Two-stage boundary** — `{Day.|Night.}` re-entered three times emits Day., Night.,
   Night., matching the oracle (and distinct from the once-only form).

#### UAT Scenarios (BDD)
```gherkin
Scenario: A three-stage sequence advances then clamps, matching the oracle
  Given a .ink source with "{red|green|blue}" behind a sticky choice
  When Maarten compiles it in-process and selects the choice four times
  Then the emitted stages are "red", "green", "blue", "blue" in order
  And the playback is identical to the inklecate-compiled equivalent

Scenario: A two-stage prose sequence renders each stage then clamps, matching the oracle
  Given a .ink source with "{Day.|Night.}" re-entered three times
  When the source is compiled and played
  Then the emitted stages are "Day.", "Night.", "Night." matching the oracle

Scenario: Shuffle is still rejected with a located error (regression guard)
  Given a .ink source using a shuffle "{~a|b}"
  When the source is compiled
  Then compilation stops with a located error naming "variable-text shuffle" as unsupported
```

#### Acceptance Criteria
- [ ] A sequence `{a|b|c}` (N stages) compiles in-process to a runnable story.
- [ ] Stages advance one per visit and clamp on the final stage.
- [ ] Playback is line-for-line identical to the inklecate oracle.
- [ ] Shuffle `{~a|b}` still rejects with a named, located error.

#### Outcome KPIs
- **Who**: a developer with an N-stage sequence.
- **Does what**: compiles and plays it natively, oracle-identically.
- **By how much**: 100% of sequence fixtures play line-for-line identical to the oracle; row 28 still rejects.
- **Measured by**: execution-equivalence oracle test over a sequence corpus + shuffle-reject assertion.
- **Baseline**: today the native compiler rejects every sequence (0% compile).

#### Technical Notes
- Depends on US-01 (proves the lowering path). Reuses existing switch codegen; no runtime change.
- Open DESIGN question: whether sequence/cycle/once share one parametrized lowering routine.

---

### US-03: Compile and play a cycle variable-text form (`{&a|b}`)

`job_id: job-native-compilation`

#### Elevator Pitch
- **Before**: Maarten's alternating idle line `{&heads|tails}` is rejected natively,
  even though the runtime can play the wrapping switch it lowers into.
- **After**: Maarten compiles a `.ink` using `{&a|b}` and gets back a runnable story
  that emits `a`, `b`, `a`, `b`, … cycling forever on each visit — line-for-line
  identical to the inklecate oracle.
- **Decision enabled**: he can write cycling lines and ship them without inklecate,
  completing the deterministic variable-text family in his native toolchain.

#### Problem
Maarten uses cycles for repeating idle and ambient effects that should loop forever
rather than settle. He needs the wrapping variable-text form to compile natively so
the last deterministic variable-text form stops forcing him back to inklecate.

#### Who
- Swift app/game developer | authoring looping idle/ambient effects | relies on cycling variable text.

#### Solution
Lower the cycle form `{&a|b}` (N stages, advance per visit, wrap via modulo over the
stage count) into the read-count-driven visit-count switch; compile and play
oracle-identically.

#### Domain Examples
1. **Happy path** — `{&heads|tails}` behind a sticky choice, selected four times,
   emits heads, tails, heads, tails; identical to the oracle.
2. **Four-stage wrap** — `{&Spring|Summer|Autumn|Winter}` re-entered five times emits
   Spring, Summer, Autumn, Winter, Spring, matching the oracle (modulo wrap over >2 stages).
3. **Clean boundary** — `{&The torch flickers.|The torch steadies.}` re-entered five
   times alternates with no off-by-one at the wrap boundary, matching the oracle.

#### UAT Scenarios (BDD)
```gherkin
Scenario: A two-stage cycle wraps forever, matching the oracle
  Given a .ink source with "{&heads|tails}" behind a sticky choice
  When Maarten compiles it in-process and selects the choice four times
  Then the emitted stages are "heads", "tails", "heads", "tails" in order
  And the playback is identical to the inklecate-compiled equivalent

Scenario: A four-stage cycle wraps via modulo, matching the oracle
  Given a .ink source with "{&Spring|Summer|Autumn|Winter}" re-entered five times
  When the source is compiled and played
  Then the emitted stages are "Spring", "Summer", "Autumn", "Winter", "Spring" matching the oracle

Scenario: Shuffle is still rejected with a located error (regression guard)
  Given a .ink source using a shuffle "{~a|b}"
  When the source is compiled
  Then compilation stops with a located error naming "variable-text shuffle" as unsupported
```

#### Acceptance Criteria
- [ ] A cycle `{&a|b}` (N stages) compiles in-process to a runnable story.
- [ ] Stages advance one per visit and wrap to the first stage via modulo over the stage count.
- [ ] Playback is line-for-line identical to the inklecate oracle.
- [ ] Shuffle `{~a|b}` still rejects with a named, located error.

#### Outcome KPIs
- **Who**: a developer with a cycling variable-text line.
- **Does what**: compiles and plays it natively, oracle-identically.
- **By how much**: 100% of cycle fixtures play line-for-line identical to the oracle; row 28 still rejects.
- **Measured by**: execution-equivalence oracle test over a cycle corpus + shuffle-reject assertion.
- **Baseline**: today the native compiler rejects every cycle (0% compile).

#### Technical Notes
- Depends on US-02 (cycle differs only in wrap vs clamp). Reuses existing switch codegen; no runtime change.

---

### US-04: Compile TheIntercept natively end-to-end and confirm shuffle still rejects

`job_id: job-native-compilation`

#### Elevator Pitch
- **Before**: the flagship `TheIntercept.ink` fixture cannot compile natively and its
  end-to-end oracle test is descoped — solely because of one once-only line (line 86).
- **After**: Maarten compiles the full `TheIntercept.ink` in-process (no inklecate, no
  JS bridge) and plays it along the committed choice script — line-for-line,
  choice-for-choice identical to the inklecate oracle; the descoped test goes green.
- **Decision enabled**: he can drop inklecate entirely for his flagship story,
  confident the whole deterministic ceiling is natively reachable — while shuffle
  still fails loud.

#### Problem
TheIntercept (28 knots, 47 stitches, 21 variables) is Maarten's comprehensive ceiling
fixture. Its native-compile end-to-end test was descoped *only* because line 86 uses a
once-only form. With rows 25-27 lowered, he needs the whole fixture to compile and
play natively — and needs proof that shuffle (the one remaining variable-text reject)
still fails loud, so nothing unsupported slips through.

#### Who
- Swift app/game developer | shipping his flagship Ink story | needs end-to-end native-compile proof + a guardrail against unsupported constructs.

#### Solution
Re-enable the descoped `TheIntercept.ink` native-compile end-to-end oracle test;
verify the full fixture compiles in-process and plays oracle-identically along the
committed choice script (hermetic — committed `.ink.json` through the pure-Swift
`Story`); verify a shuffle construct still rejects with a located error.

#### Domain Examples
1. **Happy path** — the full `TheIntercept.ink` (including line 86's once-only form)
   compiles natively and plays line-for-line, choice-for-choice identical to the
   committed inklecate oracle, no inklecate/JS bridge invoked.
2. **Descoped test green** — the previously descoped TheIntercept native-compile oracle
   test now executes and passes (no longer skipped).
3. **Shuffle guardrail** — a TheIntercept-styled scene with an added `{~a|b}` shuffle
   still rejects with a named, located error and produces no story.

#### UAT Scenarios (BDD)
```gherkin
Scenario: TheIntercept compiles natively end-to-end and plays oracle-identically
  Given the full TheIntercept.ink fixture, including its once-only form on line 86
  When Maarten compiles it in-process and plays it along the committed choice script
  Then the emitted lines and presented choices are line-for-line, choice-for-choice
    identical to the inklecate-compiled TheIntercept oracle
  And no external inklecate binary and no JS bridge are invoked during compilation or playback

Scenario: The previously descoped TheIntercept native-compile test is green
  Given the TheIntercept native-compile end-to-end oracle test, previously descoped
  When the test suite runs
  Then the test executes and passes — it is no longer skipped or descoped

Scenario: Shuffle still rejects with a located error after this feature lands
  Given a TheIntercept-styled scene that uses a shuffle "{~a|b}"
  When the source is compiled
  Then compilation stops with a located error naming "variable-text shuffle" as unsupported
  And no story is produced
```

#### Acceptance Criteria
- [ ] The full `TheIntercept.ink` compiles in-process and plays line-for-line, choice-for-choice identical to the inklecate oracle.
- [ ] No external inklecate binary and no JS bridge are invoked.
- [ ] The previously descoped TheIntercept native-compile end-to-end test executes and passes.
- [ ] A shuffle construct still rejects with a named, located error; no story produced.

#### Outcome KPIs
- **Who**: a developer with the flagship ceiling story.
- **Does what**: compiles and plays it natively, end-to-end, oracle-identically.
- **By how much**: TheIntercept.ink compiles natively end-to-end with 0 divergent lines/choices vs the oracle; row 28 still rejects with a named located error.
- **Measured by**: the re-enabled TheIntercept native-compile execution-equivalence test + a shuffle-reject assertion.
- **Baseline**: today TheIntercept's native-compile e2e test is descoped (cannot compile natively).

#### Technical Notes
- Depends on US-01, US-02, US-03 (all three deterministic forms lowered). No new lowering; integration + re-enabling one descoped test.
- Constraint: no runtime change; frozen InkSwift module untouched (D8). Shuffle/RANDOM remain out of scope (D-A).

---

## Wave: DISCUSS / [REF] Outcome KPIs (feature-level)

### Objective
Close the compiler↔runtime parity gap for the deterministic variable-text forms:
sequences, cycles, and once-only forms compile in-process and play identical to
inklecate, the flagship fixture builds natively end-to-end, and shuffle still fails
loud — all with zero runtime changes.

### Outcome KPIs

| # | Who | Does What | By How Much | Baseline | Measured By | Type |
|---|-----|-----------|-------------|----------|-------------|------|
| 1 | Developer with deterministic variable-text (rows 25-27) | compiles + plays it in-process, oracle-identical | 100% of rows 25-27 fixtures play line-for-line identical to inklecate | 0% (all three rejected today) | execution-equivalence oracle test suite (hermetic) | Leading |
| 2 | Developer with the flagship ceiling story | compiles + plays TheIntercept natively end-to-end | TheIntercept.ink compiles natively with 0 divergent lines/choices vs oracle; descoped e2e test green | descoped (cannot compile natively) | re-enabled TheIntercept execution-equivalence test | Leading |
| 3 | Developer who reaches for shuffle | still gets a clear located error, not silent acceptance | 100% of shuffle (row 28) fixtures reject with a named, located error; 0% silent acceptance | already rejected (must not regress) | shuffle-reject corpus assertion | Guardrail |
| 4 | The runtime / frozen modules | remain untouched while parity closes | 0 changes to SwiftInkRuntime engine and 0 changes to the frozen InkSwift (JS-bridge) module | n/a | code-change review (compiler-only diff) | Guardrail |

### Metric Hierarchy
- **North Star**: % of rows 25-27 fixtures that compile in-process and play line-for-line identical to the inklecate oracle (target 100%).
- **Leading indicators**: per-form oracle-equivalence pass rate (once / sequence / cycle); TheIntercept end-to-end native-compile pass.
- **Guardrail metrics**: shuffle (row 28) still rejects with a named located error (must never regress to silent acceptance); zero runtime changes; frozen InkSwift untouched.

### Measurement Plan
| KPI | Data Source | Collection Method | Frequency | Owner |
|-----|------------|-------------------|-----------|-------|
| Rows 25-27 oracle equivalence | committed inklecate `.ink.json` + pure-Swift `Story` | hermetic execution-equivalence test suite | per CI run | crafter / acceptance-designer |
| TheIntercept native e2e | TheIntercept.ink + committed oracle | re-enabled native-compile execution-equivalence test | per CI run | crafter / acceptance-designer |
| Shuffle still rejects | shuffle fixture corpus | reject-with-located-error assertion | per CI run | acceptance-designer |
| No runtime / no JS-bridge change | git diff | compiler-only diff review | per PR | nw-product-owner / reviewer |

### Hypothesis
We believe that lowering the three deterministic variable-text forms into the
visit-count switch the runtime already executes, for Maarten, will close the
documented compiler↔runtime parity gap. We will know this is true when rows 25-27
fixtures play 100% line-for-line identical to the inklecate oracle, TheIntercept.ink
compiles natively end-to-end, and shuffle still rejects with a named located error —
with zero runtime changes.

---

## Wave: DISCUSS / [REF] Driving Ports (conceptual — no new port)

No new driving port. This feature reuses the **existing compile entry point** delivered
by native-ink-compiler — it accepts `.ink` source (file or string) and yields either a
runnable story or a clear, located error. The only change is the accepted set: rows
25-27 now yield a runnable story instead of a located reject; row 28 still yields a
located reject. DESIGN defines where the lowering sits within the pipeline behind that
unchanged port.

---

## Wave: DISCUSS / [REF] Pre-requisites

- **native-ink-compiler** (delivered) — the read→parse→codegen→runtime pipeline, the
  conditional/visit-count-switch codegen, and the compile entry point this feature reuses.
- **SwiftInkRuntime** (`Story`, delivered) — already executes the visit-count switch;
  no change required.
- **inklecate** oracle + committed `.ink.json` fixtures — the hermetic correctness gate.
- **`Tests/InkSwiftTests/TheIntercept.ink`** + its committed oracle — the e2e fixture
  for US-04 (its native-compile test currently descoped at line 86).

---

## Wave: DISCUSS / [REF] Out of Scope (recorded)

- **Shuffle `{~a|b}` (row 28)** and **RANDOM / SEED_RANDOM (row 38)** — genuine runtime
  gaps; stay MUST-REJECT with a clear located error (D-A).
- Any change to the **SwiftInkRuntime** engine — the visit-count switch is already proven.
- Any change to the frozen **InkSwift** (JS-bridge) module (D8).
- Other still-rejected constructs (threads, LIST, externals — rows 36-37, 39) — unchanged.
- DESIGN-level concerns: where the lowering pass sits (parser desugar vs codegen
  lowering); whether one parametrized routine serves all three forms; type/module
  structure; access modifiers.
- Updating `ink-feature-reference.md` itself — that doc edit is a **DELIVER** task, not
  DISCUSS (recorded as a downstream note below).

---

## Wave: DISCUSS / [REF] Risks (surfaced, not managed)

| Risk | Prob | Impact | Mitigation (for DESIGN/DELIVER) |
|---|---|---|---|
| Lowered switch shape diverges subtly from inklecate's (off-by-one at clamp/wrap boundary) | Medium | High | Execution-equivalence oracle on each form, with explicit boundary fixtures (clamp at last; wrap at modulo boundary). |
| Once-only vs 2-stage sequence confusion (empty trailing stage handling) | Medium | Medium | Distinct fixtures for `{!a|}`, `{|x|}`, and `{Day.|Night.}`; oracle compares all three. |
| Sharing one lowering routine introduces a regression across forms | Low | Medium | DESIGN decides shared-vs-separate routine; per-form oracle suites catch cross-contamination. |
| Shuffle reject silently regresses once the variable-text parser path changes | Medium | High | Shuffle-reject regression guard embedded in every slice's acceptance (rows 25-27 must not accidentally swallow row 28). |
| Doc/behaviour drift after landing (reference still says rows 25-27 reject) | Medium | Medium | Downstream doc-update note recorded; the feature-reference consistency suite is the source of truth and will fail if not updated in DELIVER. |

---

## Wave: DISCUSS / [REF] Wave Decisions Summary

- **Scope Assessment: PASS** — 4 stories, 1 bounded context, ~3-4 days; 4 carpaccio
  slices (once → sequence → cycle → TheIntercept e2e). No oversize split.
- **Job reused** (not re-run): job-native-compilation (Maarten). Feature contribution
  added under it in `jobs.yaml`.
- **Persona reused**: `docs/product/personas/maarten.md` (unchanged).
- **Journey annotated, not duplicated**: `native-compilation` in
  `journeys/story-author.yaml` gains the variable-text path.
- **Decisions**: D1-D8 carried (relevance noted); D-A (scope = rows 25-27, shuffle
  excluded) and D-B (new feature, reuse job+persona) locked by Maarten.
- **Walking skeleton**: NO (brownfield — spine already delivered).
- **Shared artifact**: the visit-count-switch blueprint shape, single-sourced by the
  compiler's lowering/codegen pass; the runtime only consumes it.
- **DoR**: validated below (9 items).

---

## Wave: DISCUSS / [REF] Definition of Ready Validation

Applied per story (US-01..US-04). All stories share the same structure; the table
reports the consolidated result with per-story notes where they differ.

| DoR Item | Status | Evidence |
|----------|--------|----------|
| 1. Problem statement clear, domain language | PASS | Each story opens with a Maarten-grounded problem in Ink/toolchain domain language (once-only line-86 blocker; ambient sequences; looping idle cycles; flagship ceiling fixture). |
| 2. User/persona with specific characteristics | PASS | Reuses the existing `maarten.md` persona (toolchain owner, adopted native runtime, habituated to inklecate). Each story's "Who" narrows the context. |
| 3. 3+ domain examples with real data | PASS | Each story has 3 examples with concrete Ink (`{!The lock clicks open.|}`, `{red|green|blue}`, `{&Spring|Summer|Autumn|Winter}`, the literal TheIntercept line 86). |
| 4. UAT in Given/When/Then (3-7 scenarios) | PASS | US-01:3, US-02:3, US-03:3, US-04:3 — all within 3-7; each includes a shuffle-reject regression scenario. |
| 5. AC derived from UAT | PASS | Each story's AC checklist maps 1:1 to its scenarios and verifies the Elevator Pitch end-to-end via the oracle. |
| 6. Right-sized (1-3 days, 3-7 scenarios) | PASS | Each slice ≤1 day, 3 scenarios; reuses proven codegen; the whole feature ~3-4 days. |
| 7. Technical notes: constraints/dependencies | PASS | Each story records dependencies (US-N depends on US-(N-1)), no-runtime-change + frozen-module constraints (D8), and the open DESIGN questions (pass placement; shared routine). |
| 8. Dependencies resolved or tracked | PASS | native-ink-compiler (delivered), SwiftInkRuntime (delivered), inklecate oracle + TheIntercept fixture (available) all confirmed. Inter-story order tracked. |
| 9. Outcome KPIs defined with measurable targets | PASS | Each story + the feature level define Who/Does-what/By-how-much/Measured-by/Baseline with numeric targets (100% oracle identity; 0 divergences; shuffle 0% silent acceptance). |

### DoR Status: PASSED

---

## Wave: DISCUSS / [REF] Open Questions for DESIGN

1. **Lowering placement** — does the lowering sit at the parser level (desugar the
   variable-text source into the conditional/switch AST) or at the codegen level
   (emit the visit-count switch directly)? Both reuse proven machinery; DESIGN chooses.
2. **Shared vs separate routine** — sequence, cycle, and once differ only in the
   terminal-stage rule (clamp / wrap / stop-at-last). DESIGN decides whether one
   parametrized lowering routine serves all three or three thin variants do.
3. **Empty-stage representation** — how the empty trailing stage of `{!a|}` / `{|x|}`
   is represented in the lowered switch so it matches inklecate's emitted shape.
4. **Corpus enumeration** — the per-form fixture corpus (carried-over medium issue from
   the predecessor wave): DESIGN/DISTILL should enumerate the boundary fixtures
   (clamp-at-last, modulo-wrap, empty-trailing-stage) explicitly.

---

## Wave: DISCUSS / [REF] Downstream Doc-Update Note (due in DELIVER)

When this feature lands, `docs/product/ink-feature-reference.md` must be updated **in
the DELIVER wave** (not now):

- Move rows **25 (sequence), 26 (cycle), 27 (once-only)** from the MUST-REJECT table to
  the MUST-COMPILE table, each with its lowering reason (advance + clamp / wrap /
  stop-at-last over the read-count switch).
- Keep row **28 (shuffle)** in MUST-REJECT (still needs RANDOM).
- Update the "Known gaps / future work" section: the deterministic variable-text parity
  gap is **closed**; only shuffle remains (pending RANDOM).
- Update the "Concrete example of the parity gap" section: `TheIntercept.ink` is now
  natively compilable; the line-86 once-only form compiles.
- The feature-reference consistency suite
  (`Compiler_S5_FeatureReferenceConsistencyTests.swift`) is the source of truth and
  will need its 25-27 cases flipped from reject to compile; if the doc and suite
  disagree, the suite wins.

---

# Feature Delta: compiler-variable-text (DESIGN wave)

**Wave**: DESIGN | **Scope**: Application/component | **Mode**: PROPOSE | **Density**: lean (Tier-1)
**Architect**: Morgan (nw-solution-architect) | **Date**: 2026-06-14
**Status**: DESIGN complete — pending peer review before DISTILL handoff

> This is a **compiler-only** delta. No `Engine/`, `Decoder/`, `Facade/` execution
> change; no frozen `InkSwift` change (D8 / KPI #4). Builds on the delivered
> `native-ink-compiler` Compiler subsystem (ADR-006/007/008/009) and reuses
> `ConditionalEmitter`'s boundary pattern. All ground-truth lowering rules were
> verified against the real inklecate before this design was written.

---

## Wave: DESIGN / [REF] Domain-Driven Decisions (DDD)

D-numbered decisions, each with a verdict. These resolve the DISCUSS open questions.

| # | Decision | Verdict |
|---|---|---|
| DDD-1 | **Lowering placement** — a new codegen emitter (`VariableTextEmitter`) invoked from `RuntimeObjectEmitter.lowerBody`, parallel to `ConditionalEmitter`/`WeaveEmitter`. (Alt B parser-desugar / Alt C extend-ConditionalEmitter rejected — see ADR-010.) | ACCEPTED (Option A) |
| DDD-2 | **Shared vs separate routine** — ONE parametrized routine over `(op, bound, appendEmptyStage)`. The three forms differ only in those parameters. | ACCEPTED (Option A) |
| DDD-3 | **Stage-container shape / addressing** — absolute-qualified named stage containers (`seq{N}-s{I}` + `seq{N}-end`), emitting the `visit`/`du`/`==`/conditional-divert dispatch. No relative `.^.sN` caret arithmetic. (D5 Level-1 equivalence grants tree-shape freedom; house style is caret-free.) | ACCEPTED (Option A) |
| DDD-4 | **Empty-stage representation** — a stage container holding `pop` + divert and NO `^text` node. Once-only appends exactly one such empty stage; bare `{\|x\|}` produces empty first/last stages naturally from the `\|`-split. | ACCEPTED (resolved) |
| DDD-5 | **Gate change** — `UnsupportedConstructDetector` rejects ONLY shuffle (`~`); sequence/cycle/once pass through. The inline-conditional discriminator (top-level `:` ⇒ `ConditionalEmitter`) is preserved. | ACCEPTED |
| DDD-6 | **AST representation** — a new `ContentSegment.variableText(mode:stages:)` case, parallel to `ContentSegment.conditional`. `mode ∈ {sequence, cycle, once}`; `stages` are parsed content fragments split on top-level `\|`. | ACCEPTED |
| DDD-7 | **Emitter name / namespace** — `VariableTextEmitter`; container key namespace `seq{N}-s{I}` (stage I of the N-th variable-text group in the body) and `seq{N}-end` (shared rejoin), consistent with `cond{N}-*` / `c-N` / `g-N`. | ACCEPTED |
| DDD-8 | **Zero runtime change** — confirmed: every primitive (`visit`/`du`/`MIN`/`%`/`nop`/`pop`/`==`/conditional-divert/`#f`) is already in the engine. No `Engine/`/`Decoder/`/`Facade/` edit. | ACCEPTED (guardrail) |

---

## Wave: DESIGN / [REF] Lowering Specification (ground truth)

All three forms lower to an anonymous dispatch container flagged `#f:5`
(`Visits | CountStartOnly` → `visit` reports the 0-based own-entry read count: 0 on
first play). Per-form parameters:

| Form | Source | `OP` | `BOUND` | Append empty stage? | Stage count emitted |
|---|---|---|---|---|---|
| **sequence** `{a\|b\|c}` | S `\|`-split stages | `MIN` | `S − 1` (last index) → advance then **clamp** | no | S |
| **cycle** `{&a\|b}` | S stages | `%` | `S` (stage count) → **wrap** via modulo | no | S |
| **once-only** `{!a\|b}` | S source stages | `MIN` | `S` (new last index) → advance then **blank** | **yes (1)** | S + 1 |
| **bare** `{\|x\|}` | NOT special — a plain **sequence**; `\|`-split yields `["", "x", ""]` | `MIN` | `S − 1` | no | S (= 3) |

Dispatch body shape (per form, parametrized):

```
ev visit BOUND OP /ev                  ← compute clamped/wrapped index
ev du 0 == /ev  {"->":"seqN-s0","c":true}
ev du 1 == /ev  {"->":"seqN-s1","c":true}
…one per stage…
nop
namedContent:
  seqN-s0: [ pop, <^text0?>, {"->":"seqN-end"} ]   ← empty stage omits ^text
  seqN-s1: [ pop, <^text1?>, {"->":"seqN-end"} ]
  …
  seqN-end: [ <line's trailing segments + rest of enclosing body> ]
dispatch container flag: #f = 5
```

- `du` duplicates the computed index; each stage starts with `pop` to discard it.
- An **empty stage** has no `^text` node — just `[pop, {divert}]`.
- Worked examples: `{!alpha|beta}` → 3 stages `[alpha, beta, ""]`, `visit 2 MIN`;
  `{!alpha|beta|gamma}` → 4 stages, `visit 3 MIN`; TheIntercept line 86
  `{|I rattle…|}` → 3-stage sequence `["", "I rattle…", ""]`, `visit 2 MIN`.

**Engine support (evidence for zero runtime change)** — `visit` `TreeWalker.swift:180`
(0-based own read count, matching inklecate), `du` `:144`, `MIN`/`MAX` `:287`, `%`
`:274`, `nop` `:166`, `pop`/`ev`/`/ev` (control commands `InkDecoder.swift:8`); `==`,
conditional diverts (`"c":true`), `#f` flag, and named containers all proven by
`ConditionalEmitter`.

---

## Wave: DESIGN / [REF] Component Decomposition

| Component | Path | Decision | Responsibility |
|---|---|---|---|
| `VariableTextEmitter` | `Compiler/Codegen/VariableTextEmitter.swift` | **CREATE NEW** | Stateless `enum`; one parametrized `lower(mode:stages:continuation:keyPrefix:named:lowerBranch:)` over `(op, bound, appendEmptyStage)`. Emits `visit`/`du`/`==`/conditional-divert dispatch + named `seq{N}-s{I}` stage containers + shared `seq{N}-end` rejoin; stamps `#f:5`. |
| `ContentSegment.variableText` | `Compiler/AST/CompilerAST.swift` | **CREATE NEW** (enum case) | New AST case `variableText(mode: VariableTextMode, stages: [...])` parallel to `.conditional`. New small `VariableTextMode` enum `{sequence, cycle, once}`. |
| variable-text parse rule | `Compiler/Parser/InkParser*.swift` | **CREATE NEW** (rule) + EXTEND file | Recognise a brace group whose body has top-level `\|` and no top-level `:`; read the leading marker (`&`→cycle, `!`→once, none→sequence); `\|`-split the body into stages; build `.variableText`. |
| `RuntimeObjectEmitter.lowerBody` | `Compiler/Codegen/RuntimeObjectEmitter.swift` | **EXTEND** | Detect a `.variableText` segment in a content line (parallel to the existing `.conditional` branch) and invoke `VariableTextEmitter`, threading the line suffix + rest-of-body as the continuation. |
| `UnsupportedConstructDetector` | `Compiler/Parser/UnsupportedConstructDetector.swift` | **EXTEND** (gate change) | `variableTextConstruct(of:)` returns a construct only for the `~` (shuffle) marker; sequence/cycle/once return `nil` (pass through). Conditional discriminator unchanged. |

C4 component diagram (extended Compiler subsystem) — see the SSOT subsection
`compiler-variable-text (Feature Addition)` in `docs/product/architecture/brief.md`.

---

## Wave: DESIGN / [REF] Driving & Driven Ports

**No new port.** The feature reuses the existing compile entry
(`InkCompiler.compile(source:)` → `StoryBlueprint`, surfaced via the `Story` facade).
The accepted set widens — rows 25–27 now yield a runnable story instead of a located
reject; row 28 still rejects. No driven adapter is added or changed (no filesystem,
network, time, or subprocess dependency is introduced; `SourceReader` is untouched), so
no new `probe()` is required — the existing `SourceReader`/`InkDecoder` probes cover the
substrate (Earned Trust, principle 13). Per principle 12, `VariableTextEmitter` is a
**pure function** (return-only) contract shape: it takes parsed stages + collectors and
returns `[NodeKind]` while registering containers into an `inout` `named` collector —
the identical bounded-mutation contract `ConditionalEmitter` already honours; it
performs no I/O and no global side effect.

---

## Wave: DESIGN / [REF] Technology Choices

**No new dependency.** No `Package.swift` change. The emitter is pure Swift over the
existing internal `NodeKind`/`ContainerNode` types (R2 preserved). R5 holds:
`Compiler/` constructs `Decoder/` node types, does not import `Engine/`, and calls no
`JSONSerialization`. Enforcement is the existing SwiftLint `custom_rules` R1/R3/R5 gates
plus Swift access control — no new tooling needed.

---

## Wave: DESIGN / [REF] Decisions Table

| # | Decision | Rationale | ADR |
|---|---|---|---|
| VT-1 | New `VariableTextEmitter` invoked from `lowerBody`, parallel to `ConditionalEmitter`. | One-emitter-per-concern boundary; variable-text dispatches on visit-index, not a boolean guard. | ADR-010 |
| VT-2 | One parametrized routine over `(op, bound, appendEmptyStage)`. | Ground truth shows the forms are identical modulo those three parameters. | ADR-010 |
| VT-3 | Absolute-qualified named stage containers (`seq{N}-s{I}`/`seq{N}-end`); `#f:5` on the dispatch container. | House style (caret-free); Level-1 equivalence grants tree-shape freedom. | ADR-010 |
| VT-4 | Empty stage = `pop` + divert, no `^text`; once appends one; bare `{\|x\|}` is a plain sequence. | Matches inklecate's emitted shape; resolves DISCUSS empty-stage open question. | ADR-010 |
| VT-5 | Gate change: reject ONLY shuffle; preserve the inline-conditional `:` discriminator. | Closes rows 25–27 while keeping row 28 fail-loud (D-A, regression-guarded). | ADR-010 |

---

## Wave: DESIGN / [REF] Reuse Analysis (MANDATORY hard gate)

Every overlapping component classified. **CREATE NEW = 3** (the new emitter, the AST
case + mode enum, the parse rule). **EXTEND = 3.** **REUSE AS-IS = 7.** Every runtime
integration point is REUSE or EXTEND — zero unjustified CREATE NEW.

**Contract-shape column** (principle 12 — Effect Isolation): each overlapping component
cites its contract shape, its mutation universe, and the assertion mechanism the crafter
will use. The single assertion mechanism for every behavioural component is the **oracle
Level-1 execution-equivalence** suite (committed `.ink.json` through the pure-Swift
`Story`).

| Existing / new component | File | Overlap | Decision | Contract shape · universe | Justification |
|---|---|---|---|---|---|
| `VariableTextEmitter` | `Compiler/Codegen/VariableTextEmitter.swift` | No prior variable-text lowering exists | **CREATE NEW** | **pure-function (return-only)** · returns `[NodeKind]`; registers stage/end containers via `inout named` (aggregate-bounded, same universe as `ConditionalEmitter`); **no I/O, no global side effect**. Assertion = oracle. | New concern (visit-index dispatch, not boolean-guard). A god-object effect (writing to disk/global state) is structurally non-representable: the type is `(...) -> [NodeKind]`. |
| `ContentSegment` + `VariableTextMode` | `Compiler/AST/CompilerAST.swift` | Adds one enum case + one small enum | **CREATE NEW** (case) | **immutable value type** · no mutation. Assertion = compiler exhaustiveness. | A `.variableText` case parallel to `.conditional`; no existing case fits. |
| variable-text parse rule | `Compiler/Parser/InkParser*.swift` | Adds a content-segment rule | **CREATE NEW** (rule) | **pure-function (return-only)** · returns parsed segments; cursor-bounded read. Assertion = oracle + parser unit tests. | New syntax recognition (top-level `\|`, no top-level `:`, leading marker → mode). File EXTENDed; the rule itself is new. |
| `RuntimeObjectEmitter.lowerBody` | `Compiler/Codegen/RuntimeObjectEmitter.swift` | `.conditional`-segment detection + `ConditionalEmitter` dispatch | **EXTEND** | **bounded-change** · declared mutation set: appends to local `children`, registers into `inout named` (aggregate-bounded). Assertion = oracle. | One additive `.variableText` branch parallel to the proven `.conditional` branch; reuses `branchLowerer`, `inlineContinuationStatements`, and the `-end` rejoin contract. |
| `UnsupportedConstructDetector` | `Compiler/Parser/UnsupportedConstructDetector.swift` | `variableTextConstruct(of:)` reject scan | **EXTEND** (gate) | **pure-function (return-only)** · returns construct name or `nil` / throws located error; no mutation. Assertion = oracle + shuffle-reject regression guard. | Narrow the reject set to shuffle only; keep the `~` path and the conditional `:` discriminator. |
| `ConditionalEmitter` | `Compiler/Codegen/ConditionalEmitter.swift` | Boundary pattern (named containers + `-end` rejoin via `lowerBranch`) | **REUSE AS-IS** (template) | **pure-function / bounded-change** (proven in production) · same `inout named` aggregate universe `VariableTextEmitter` adopts. | Not modified; copied-pattern, not shared-code. New emitter mirrors its `BranchLowerer`/`ExpressionLowerer` typealiases and `nextOrdinal`/`key`/`path` helpers. |
| `branchLowerer` / `lowerBody` recursion | `Compiler/Codegen/RuntimeObjectEmitter.swift` | Lowering a stage/continuation body | **REUSE AS-IS** | **bounded-change** (proven) · `inout named` aggregate. Assertion = oracle. | Stages and the `-end` continuation are lowered via the same `branchLowerer` closure the conditional path uses. |
| `ContainerNode` | `Decoder/ContainerNode.swift` | Codegen output type; `flags` carries `#f:5` | **REUSE AS-IS** | **immutable value type** · constructed, not mutated. | Stage/dispatch containers are `ContainerNode`s; `flags: 5` sets the visit-count flag. |
| `NodeKind` | `Decoder/NodeKind.swift` | `.controlCommand`, `.nativeFunction`, `.divert(…,isConditional:)`, `.text` | **REUSE AS-IS** | **immutable value type** · no new case. | All emitted instructions are existing cases — no new `NodeKind` case (unlike Tier-3). |
| `visit` / `du` / `MIN` / `%` / `nop` / `pop` ops | `Engine/TreeWalker.swift` (180/144/287/274/166/149) | Runtime execution of the dispatch | **REUSE AS-IS** | **bounded-change** (engine state) · already shipped & oracle-proven. | Evidence for zero runtime change (KPI #4). |
| `==` + conditional divert (`"c":true`) | `Engine/InkEngine.swift` / `Decoder/InkDecoder.swift` | Stage selection | **REUSE AS-IS** | **bounded-change** (engine state) · already shipped. | Same pathway `ConditionalEmitter` lowers onto. |
| Oracle harness + corpus | `Tests/SwiftInkRuntimeTests/Acceptance/` + `.ink`/`.ink.json` fixtures | Correctness gate | **REUSE / EXTEND** | n/a (test harness) | Hermetic Level-1 execution-equivalence; add per-form + boundary + shuffle-reject fixtures (DISTILL/DELIVER). |
| `TheIntercept.ink` + committed oracle | `Tests/SwiftInkRuntimeTests/` | US-04 e2e | **REUSE** | n/a (fixture) | Re-enable the descoped native-compile e2e once line 86 compiles. |

---

## Wave: DESIGN / [REF] Open Questions (deferred)

| # | Question | Owner |
|---|---|---|
| OQ-1 | Boundary-fixture corpus — **front-loaded to DISTILL** (DISCUSS risk register flags off-by-one at clamp/wrap as Medium/High). Minimum set as explicit acceptance criteria per US-01/02/03: sequence clamp-at-last, cycle modulo-wrap boundary, once-only empty-trailing-stage, bare `{\|x\|}`, 2-stage once vs 2-stage sequence distinction, **plus a mixed variable-text + conditional fixture** (see OQ-3). | DISTILL (acceptance-designer) |
| OQ-2 | Whether rich inline content beyond text+interpolation appears inside stages in the broader corpus (TheIntercept needs only text+interpolation). Scope per corpus during DISTILL; emitter recursion via `branchLowerer` already supports nested content if needed. | DISTILL / DELIVER |
| OQ-3 | Stage-container key collision when a body mixes variable-text and conditionals. Distinct prefixes (`seq{N}-*` vs `cond{N}-*`) make collision impossible **by construction**. **Promoted to a DISTILL acceptance criterion** (not ad-hoc DELIVER discovery): "a body mixing variable-text and conditionals produces no key collisions and plays oracle-identically" — backed by a mixed-construct fixture in the OQ-1 corpus. | DISTILL (AC) + DELIVER (RED verify) |

---

## Wave: DESIGN / [REF] Outcome Collision Check

**Not applicable.** No `docs/product/outcomes/registry.yaml` exists in this repo, and
the feature reuses the existing `job-native-compilation` outcome with no new typed
contract surface. The check was correctly skipped (no registry; no new contract).

---

## Wave: DESIGN / [REF] Upstream Changes / Back-Propagation

**None.** No DISCUSS decision is reversed. The ground truth confirms DISCUSS's
"zero runtime change" premise (every op already in the engine — line numbers cited) and
the "one shared routine" hypothesis (DDD-2). No contradiction found; no back-propagation
required.

---

## Wave: DESIGN / [REF] Wave Decisions Summary

- **Mode**: PROPOSE; all four design questions resolved with recommendations accepted
  (DDD-1 emitter, DDD-2 one parametrized routine, DDD-3 absolute-named addressing,
  DDD-4 empty-stage = `pop`+divert).
- **Reuse Analysis**: 3 CREATE NEW (emitter, AST case+mode, parse rule), 3 EXTEND
  (`lowerBody`, `UnsupportedConstructDetector` gate, parser file), 7 REUSE AS-IS.
- **ADR**: ADR-010 (Accepted) — variable-text lowering via one parametrized emitter.
- **Constraints honoured**: compiler-only diff; no `Engine/`/`Decoder/`/`Facade/`/frozen
  `InkSwift` change (D8 / KPI #4); R2/R5 preserved; shuffle still rejects.
- **Correctness gate**: hermetic Level-1 execution-equivalence (committed `.ink.json`
  through pure-Swift `Story`).
- **No new dependency, no new port, no new `NodeKind` case.**
