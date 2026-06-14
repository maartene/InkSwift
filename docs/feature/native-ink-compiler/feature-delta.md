<!-- markdownlint-disable MD024 -->
# Feature Delta: native-ink-compiler (DISCUSS wave)

**Feature**: native-ink-compiler
**Wave**: DISCUSS
**Analyst**: Luna (nw-product-owner)
**Date**: 2026-06-14
**Persona**: Maarten — Swift app developer embedding Ink stories
**Job**: job-native-compilation (new; validated this wave)
**Status**: DISCUSS complete — pending peer review + DoR gate before DESIGN handoff

> Density: lean (Tier-1 [REF] sections). DISCUSS describes intent and behaviour
> only — no API signatures, type names, or access modifiers (DESIGN concerns).

---

## Wave: DISCUSS / [REF] Required Reading Checklist

- ✓ `docs/product/jobs.yaml` — existing jobs job-story-playback (Maarten), job-story-logic-verification (Raya)
- ✓ `docs/product/journeys/story-author.yaml` — persona Raya; GWT mental model
- ✓ `docs/product/architecture/brief.md` — full read (892 lines); Feature Coverage Matrix (rows 1-39) + parallel-module architecture
- ✓ `docs/research/ink-compiler-feasibility.md` — GO verdict; phased plan; weave = highest risk; hand-rolled parser recommendation; oracle strategy
- ✓ `docs/evolution/2026-06-01-native-runtime.md` — deferred items (lists/externals/threads) confirm out-of-runtime-scope
- ⊘ `docs/product/personas/` — did not exist; created `personas/maarten.md` this wave

---

## Wave: DISCUSS / [REF] Job Statement (JTBD)

**job-native-compilation** (added to `docs/product/jobs.yaml`):

> When I author an Ink story for my Swift app and need to turn it into something my
> app can play, I want to compile it to a runnable story entirely within my Swift
> toolchain, so I can build and ship without depending on the external inklecate
> binary — and get a clear error the moment I use a feature my runtime cannot play,
> instead of shipping a silently broken story.

**Four forces** (validated):
- **Push**: runtime is pure Swift, but every build still shells out to the external
  inklecate (C#) binary — install, version-match, invoke out-of-process everywhere.
- **Pull**: one Swift toolchain that both compiles and runs; in-process compile to a
  directly-runnable story; no external binary.
- **Anxiety**: a hand-written Swift compiler might diverge silently from inklecate,
  or accept an unsupported feature and emit a subtly wrong story.
- **Habit**: an established `inklecate file.ink -o file.ink.json` step; trust in
  inklecate as ground truth.

**Functional / emotional / social dimensions**:
- Functional: convert `.ink` -> runnable story, in-process, within supported bounds.
- Emotional: from *dependent / wary* to *confident / self-sufficient* (one toolchain).
- Social: a fully native Swift Ink stack is a credible, dependency-light story to
  share with the Swift community (the project would be the first native Swift Ink compiler).

**Relationship to existing jobs**: completes the toolchain that **job-story-playback**
began. Playback removed the JavaScript engine from the RUN side; native compilation
removes the inklecate binary from the BUILD side. Same persona (Maarten). Raya
(job-story-logic-verification) benefits secondarily via a shorter authoring loop.

---

## Wave: DISCUSS / [REF] Scope Assessment (Elephant Carpaccio Gate)

The research estimates 10-30 person-weeks for a *full* Ink compiler. That would be
oversized. **This feature is deliberately bounded to the runtime's existing
capabilities** (matrix rows 1-35 supported; 25-28 + 36-39 rejected), which removes
the most expensive constructs (lists, threads, externals, sequences/shuffle) from
the *compile* path entirely — they become reject-with-error cases, not codegen work.

**Scope Assessment: PASS (with planned splitting).** Bounded scope = 7 carpaccio
slices (S0-S6). Single bounded context (the new compiler), one integration contract
(the runtime's runnable-story input). S3 (weave) and S4 (conditionals/functions/
tunnels) are flagged for further splitting if any single slice exceeds ~1 day —
splitting guidance is recorded in each slice brief. No slice touches >1 bounded
context. Estimated 7-12 thin deliverables once S3/S4 split. Walking skeleton (S0)
is the thinnest end-to-end vertical and ships first.

No user-confirmation-required oversize split: the feature stays one feature; slices
are the unit of incremental delivery, all under the one job.

---

## Wave: DISCUSS / [REF] Locked Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Compiler scope == runtime scope (matrix rows 1-35 supported). | The compiler exists to feed this runtime; accepting more than the runtime plays would ship silent breakage. |
| D2 | Unsupported constructs (rows 25-28, 36-39) are **rejected with a clear, located error**, never compiled. | User directive: "unsupported features should provide a clear error message, not fail silently." |
| D3 | Primary output is an in-process **runnable story the runtime consumes directly** (no JSON round-trip). | Core value: one Swift toolchain, compile to run. |
| D4 | JSON output is a **secondary, lower-priority** artifact, valued for oracle structural comparison + caching/interop. | User: "JSON representation is useful but less important." |
| D5 | Correctness is judged by **execution-equivalence against the inklecate oracle** (Level 1), with structural JSON comparison as supplementary (Level 2). | Research-recommended; robust to cosmetic JSON differences. |
| D6 | The compiler performs **compile-time obligations the runtime assumes inklecate did**: CONST inlining (row 17) and choice-flag / invisible-default encoding (row 10). | The runtime does NOT do these; omitting them mis-plays supported stories. |
| D7 | A **supported/unsupported feature reference document** is a first-class deliverable (S5), derived from the runtime matrix. | User: "a clear description of the Ink features that are and are not supported is needed." |
| D8 | The frozen `InkSwift` (JS-bridge) module is **untouched**. | Established project boundary. |

---

## Wave: DISCUSS / [REF] Supported vs Unsupported Scope (locked)

**MUST COMPILE** (runtime supports — matrix rows 1-35): text output/newlines;
knots; stitches; diverts (all forms incl. relative/anchor); relative paths;
plain/bracketed/sticky/conditional choices; gathers + labeled gathers; read counts;
glue; VAR globals; CONST (with compile-time inlining); temp vars; variable
assignment; variable read in output; arithmetic & logic operators
(`+ - * / % == != > < && || !`); inline conditionals `{c: a|b}`; block conditionals
(if/else if); switch-style conditionals; functions `=== f(params) ===`; inline
function calls `{f()}`; string interpolation; tags `#tag`; save/restore (no compiler
action — runtime concern); tunnels `-> knot ->`; reference parameters `ref x`.

**MUST REJECT WITH A CLEAR, LOCATED ERROR** (runtime does NOT support — rows 25-28,
36-39): variable-text sequences `{a|b|c}`, cycles `{&}`, once-only `{!}`,
shuffle `{~}`; threads; LIST declarations; RANDOM / SEED_RANDOM; external functions
(`EXTERNAL` / `x()`).

---

## Wave: DISCUSS / [REF] Walking-Skeleton Strategy

Thinnest end-to-end vertical (S0): compile a single line of plain text
(`Hello, world.`) in-process into a runnable story, play it in SwiftInkRuntime,
and confirm the emitted line matches the inklecate oracle. This proves the entire
pipeline — read -> parse -> codegen -> runtime-consumable structure -> execute ->
oracle match — on the smallest possible input, deliberately touching no language
feature beyond plain text. Everything else is incremental once the spine exists.

---

## Wave: DISCUSS / [REF] User Stories

Stories trace N:1 to **job-native-compilation**. Each maps to a slice brief in
`slices/`. Per the project DISCUSS-scope rule, the "After" line of each Elevator
Pitch names a conceptual user-invocable entry point ("compile a .ink … and get
back a runnable story / a clear error"), not a Swift signature.

### US-01: Compile and play one line of plain text (walking skeleton)

#### Elevator Pitch
- **Before**: Maarten must run the external inklecate binary to turn even a
  one-line `.ink` into something his Swift app can play.
- **After**: Maarten compiles a `.ink` source in-process and gets back a runnable
  story that plays `Hello, world.` — with no external binary in the loop.
- **Decision enabled**: he can decide to drop inklecate from his build for this
  story, because the pure-Swift path produces the same output.

#### Problem
Maarten is a Swift app developer who has already removed the JavaScript engine from
his app via the native runtime. He finds it frustrating that his build still
shells out to the external inklecate (C#) binary just to compile a story before the
runtime can play it.

#### Who
- Swift app/game developer | owns his build toolchain | wants the whole Ink pipeline pure-Swift.

#### Solution
Compile a single-line plain-text `.ink` source in-process into a story the runtime
plays directly; emitted text matches the inklecate oracle.

#### Domain Examples
1. **Happy path** — Maarten compiles `Hello, world.`; the runtime emits exactly
   `Hello, world.`; inklecate on the same source, played through the runtime, emits
   the identical line.
2. **Edge case** — Maarten compiles a one-line source with a trailing newline; the
   emitted line matches the oracle (no spurious blank line).
3. **Boundary** — Maarten compiles an empty source; the result is a story that
   produces no output and ends cleanly, matching the oracle.

#### UAT Scenarios (BDD)
```gherkin
Scenario: A one-line plain-text story compiles and plays, matching the oracle
  Given a .ink source containing exactly "Hello, world."
  When Maarten compiles it through the in-process compile entry point
  And plays the compiled story through the runtime
  Then the runtime emits exactly "Hello, world."
  And no external inklecate binary was invoked during compilation
  And the emitted text matches the inklecate-compiled equivalent played through the runtime

Scenario: A trailing newline does not produce a spurious blank line
  Given a .ink source with one line of text followed by a blank line
  When the source is compiled and played
  Then the emitted output matches the inklecate oracle exactly

Scenario: An empty source compiles to a story that ends cleanly
  Given an empty .ink source
  When the source is compiled and played
  Then the story produces no output and ends, matching the oracle
```

#### Acceptance Criteria
- [ ] A one-line plain-text source compiles in-process to a runnable story.
- [ ] The runtime plays it and emits the source line exactly.
- [ ] Output is identical to the inklecate-compiled equivalent (execution-equivalence).
- [ ] No external inklecate process is invoked during native compilation.

#### Outcome KPIs
- **Who**: a developer compiling a trivial story.
- **Does what**: compiles and plays it entirely in-process.
- **By how much**: 100% of the pipeline stages exercised with zero external-binary invocations; output byte-identical to oracle for the skeleton corpus.
- **Measured by**: the skeleton oracle-equivalence test + a check that no inklecate subprocess is spawned.
- **Baseline**: today, 0% of compilation is in-process (inklecate required for all).

#### Technical Notes
- Integration contract: the runnable-story shape is owned by the runtime (no JSON round-trip). Dependency: SwiftInkRuntime Story input (available, delivered).
- Constraint: do not modify the frozen InkSwift module (D8).

---

### US-02: Compile a linear core-flow story (knots, stitches, diverts, glue)

#### Elevator Pitch
- **Before**: even a simple linear multi-knot story needs the external inklecate to build.
- **After**: Maarten compiles a multi-knot linear `.ink` in-process and the runtime
  plays it through, diverts and glue resolved exactly as inklecate would.
- **Decision enabled**: he can author and ship linear stories with no external compiler.

#### Problem
Maarten wants to compile the linear (choice-free) sections of his story — knots,
stitches, diverts, glue — without the external binary, and trust the flow lands
exactly where inklecate would.

#### Who
- Swift app/game developer | authoring linear narrative passages | needs flow fidelity.

#### Solution
Compile core flow constructs (rows 1-5, 15) to a runnable story; play it; match the oracle.

#### Domain Examples
1. **Happy path** — A 3-knot story (`intro -> investigation -> conclusion`) with a
   stitch plays straight through, matching the oracle line-for-line.
2. **Relative divert** — A knot diverts via `.^.helper`; the runtime lands on the
   right content, matching the oracle.
3. **Glue** — Two lines joined by `<>` render as one line with no break, matching the oracle.

#### UAT Scenarios (BDD)
```gherkin
Scenario: A multi-knot linear story compiles and plays, matching the oracle
  Given a .ink source with knots, a stitch, absolute and relative diverts, and glue
  When Maarten compiles it in-process and plays it to the end
  Then the emitted lines are identical to the inklecate-compiled equivalent

Scenario: A divert to a named knot lands at the right content
  Given a .ink source whose first knot diverts to a later named knot
  When the story is compiled and played
  Then the runtime continues at the diverted knot's content, matching the oracle

Scenario: Glue joins two lines exactly as inklecate produces them
  Given a .ink source with two lines joined by "<>"
  When the story is compiled and played
  Then the two lines render as one, matching the oracle
```

#### Acceptance Criteria
- [ ] Knots, stitches, and all divert forms (absolute, relative `.^`, anchor) resolve to oracle-matching flow.
- [ ] Glue joins lines identically to the oracle.
- [ ] A complete linear story plays end-to-end matching the oracle.

#### Outcome KPIs
- **Who**: a developer with a linear story.
- **Does what**: compiles and plays it natively.
- **By how much**: a linear supported story plays line-for-line identical to the oracle (0 divergent lines).
- **Measured by**: oracle execution-equivalence test over a linear-story corpus.
- **Baseline**: 0 linear stories compile natively today.

#### Technical Notes
- Depends on US-01. Constraint: scope limited to matrix rows 1-5, 15.

---

### US-03: Compile a state-driven story (variables, expressions, CONST inlining)

#### Elevator Pitch
- **Before**: stories whose text depends on variables/CONSTs need inklecate to build.
- **After**: Maarten compiles a variable- and CONST-driven `.ink` in-process and the
  runtime renders the computed values exactly as inklecate would.
- **Decision enabled**: he can ship state-driven narrative without the external compiler.

#### Problem
Maarten's story uses a score variable and named CONSTs to drive its text. He needs
these to compile natively — and crucially, the compiler must inline CONSTs (the
runtime assumes that was done), or the story will mis-play with no error.

#### Who
- Swift app/game developer | authoring state-driven narrative | relies on CONSTs and arithmetic.

#### Solution
Compile VAR/CONST/temp, assignment, variable-read-in-output, operators, and string
interpolation (rows 16-21, 31), performing CONST inlining at compile time; match the oracle.

#### Domain Examples
1. **Happy path** — `VAR score = 3`; `Score: {score}` renders `Score: 3`, matching the oracle.
2. **CONST comparison** — a variable compared against `CONST CHESS` resolves the
   same branch as inklecate, with the CONST inlined as a literal in the compiled story.
3. **Arithmetic** — `{2 + 3 * 4}` renders `14`, matching the oracle.

#### UAT Scenarios (BDD)
```gherkin
Scenario: A variable read in output matches the oracle
  Given a .ink source declaring "VAR score = 3" and printing "Score: {score}"
  When the story is compiled in-process and played
  Then the runtime emits "Score: 3", matching the inklecate-compiled equivalent

Scenario: A CONST used in a comparison resolves identically to the oracle
  Given a .ink source declaring CONSTs and comparing a variable against one
  When the story is compiled and played
  Then the comparison result and resulting text match the oracle
  And the compiled story contains the CONST inlined as a literal

Scenario: An arithmetic expression in output matches the oracle
  Given a .ink source printing "{2 + 3 * 4}"
  When the story is compiled and played
  Then the runtime emits "14", matching the oracle
```

#### Acceptance Criteria
- [ ] VAR/temp declaration, assignment, and read-in-output match the oracle.
- [ ] CONSTs are inlined as literals at compile time (no runtime CONST lookup) and comparisons match the oracle.
- [ ] Arithmetic and logic operators evaluate identically to the oracle.

#### Outcome KPIs
- **Who**: a developer with a state-driven story.
- **Does what**: compiles it natively with correct value rendering.
- **By how much**: state-driven supported story plays identical to the oracle; CONST inlining verified present (0 runtime CONST lookups).
- **Measured by**: oracle equivalence test + a structural check that CONSTs are literals in the compiled output.
- **Baseline**: 0 state-driven stories compile natively today.

#### Technical Notes
- Depends on US-02. Compile-time obligation D6 (CONST inlining). Split into US-03a/b if >1 day.

---

### US-04: Compile an interactive story (choices, gathers, read counts)

#### Elevator Pitch
- **Before**: interactive stories (the majority of real Ink) need inklecate to build.
- **After**: Maarten compiles a branching `.ink` in-process and the runtime presents
  the same choices and follows the same post-choice flow as inklecate.
- **Decision enabled**: he can author and ship interactive stories with no external compiler.

#### Problem
Maarten's story branches with choices and converges on gathers, and tracks how
often a knot is visited. He needs all of this to compile natively — including the
choice-flag and invisible-default encoding the runtime assumes was done at compile time.

#### Who
- Swift app/game developer | authoring branching, interactive narrative | the core Ink use case.

#### Solution
Compile plain/bracketed/sticky/conditional choices, gathers + labels, and read
counts (rows 6-14), emitting the choice-flag/invisible-default encoding; match the
oracle along fixed choice paths.

#### Domain Examples
1. **Happy path** — a scene with three choices and a gather presents the same
   choices as the oracle; picking index 1 leads to identical text.
2. **Once-only vs sticky** — a `*` choice disappears after selection; a `+` choice
   remains — both matching the oracle on replay.
3. **Conditional choice** — `* {has_key} Unlock the door` appears only when
   `has_key` is true, matching the oracle.

#### UAT Scenarios (BDD)
```gherkin
Scenario: A story with choices presents identical choices to the oracle
  Given a .ink source with plain, bracketed, and sticky choices and a gather
  When the story is compiled in-process and played
  Then the choices presented at each turn match the inklecate-compiled equivalent
  And selecting a choice index leads to identical subsequent text

Scenario: A once-only choice is suppressed after selection, matching the oracle
  Given a .ink source with a once-only (*) choice already selected once
  When the story is replayed to the same point
  Then the once-only choice is no longer presented, matching the oracle

Scenario: A sticky choice remains after selection, matching the oracle
  Given a .ink source with a sticky (+) choice already selected once
  When the story is replayed to the same point
  Then the sticky choice is still presented, matching the oracle

Scenario: A conditional choice appears only when its condition holds
  Given a .ink source with a "* {has_key} Unlock the door" choice
  When the story is compiled and played with has_key true then false
  Then the choice is present when true and absent when false, matching the oracle
```

#### Acceptance Criteria
- [ ] Plain, bracketed, sticky, and conditional choices present and behave identically to the oracle.
- [ ] Gathers (incl. labeled, multi-level) converge flow identically to the oracle.
- [ ] Read counts (knot visit counters) match the oracle.
- [ ] The compiled output carries the choice-flag bitfield + invisible-default encoding.

#### Outcome KPIs
- **Who**: a developer with an interactive story.
- **Does what**: compiles it natively with correct choice mechanics.
- **By how much**: interactive supported story plays identical to the oracle along all tested choice paths (0 divergences).
- **Measured by**: oracle equivalence test over multiple choice paths.
- **Baseline**: 0 interactive stories compile natively today.

#### Technical Notes
- Depends on US-02, US-03. **Weave resolution is the research-flagged highest-risk
  algorithm** — DESIGN should consider a spike. Split into US-04a/b/c if >1 day.

---

### US-05: Compile the full supported ceiling (conditionals, functions, tunnels, ref params, tags)

#### Elevator Pitch
- **Before**: stories using conditionals, functions, tunnels, or ref params need inklecate.
- **After**: Maarten compiles a story exercising the full supported set in-process and
  the runtime plays it identically to inklecate — up to The Intercept ceiling.
- **Decision enabled**: he can drop inklecate entirely for any story within the supported set.

#### Problem
Maarten's richer scenes use inline/block/switch conditionals, helper functions,
tunnels, and reference parameters. He needs the complete supported set to compile
natively so the whole story — not just the simple parts — runs without inklecate.

#### Who
- Swift app/game developer | authoring advanced narrative logic | targets the supported ceiling.

#### Solution
Compile conditionals (inline/block/switch), functions + inline calls, tunnels,
reference parameters, and tags (rows 22-24, 29-35); match the oracle.

#### Domain Examples
1. **Inline conditional** — `{visited: again|first time}` renders the right branch
   each way, matching the oracle.
2. **Function call** — `{double(5)}` renders `10`, matching the oracle.
3. **Tunnel + ref param** — `-> detour ->` returns to the call site; `raise(ref score)`
   mutates the caller's variable — both matching the oracle.

#### UAT Scenarios (BDD)
```gherkin
Scenario: An inline conditional renders the correct branch, matching the oracle
  Given a .ink source printing "{visited: again|first time}"
  When compiled and played with the condition false then true
  Then the rendered branch matches the oracle in each case

Scenario: A function call in output returns a value matching the oracle
  Given a .ink source defining a function and printing "{double(5)}"
  When compiled and played
  Then the runtime emits "10", matching the oracle

Scenario: A tunnel runs and returns to the call site, matching the oracle
  Given a .ink source that tunnels "-> detour ->" and continues afterwards
  When compiled and played
  Then the detour content then the continuation play in order, matching the oracle

Scenario: A reference parameter mutates the caller's variable, matching the oracle
  Given a .ink source calling "raise(ref score)" that increments score
  When compiled and played
  Then score reflects the mutation, matching the oracle
```

#### Acceptance Criteria
- [ ] Inline, block, and switch conditionals render the correct branch matching the oracle.
- [ ] Functions and inline calls return and emit values matching the oracle.
- [ ] Tunnels run and return to the call site matching the oracle.
- [ ] Reference parameters mutate the caller's variable matching the oracle.
- [ ] Tags are emitted matching the oracle.

#### Outcome KPIs
- **Who**: a developer with an advanced-logic story.
- **Does what**: compiles the full supported set natively.
- **By how much**: a story exercising the complete supported ceiling plays identical to the oracle (0 divergences).
- **Measured by**: oracle equivalence test over a ceiling-exercising corpus (Intercept-styled).
- **Baseline**: 0 advanced-logic stories compile natively today.

#### Technical Notes
- Depends on US-03, US-04. Save/restore is a runtime concern (no compiler action). Split into US-05a/b/c if >1 day.

---

### US-06: Reject unsupported features with a clear, located error

#### Elevator Pitch
- **Before**: if a story uses a feature the runtime can't play, the author risks a
  silently broken story discovered only at runtime (or never).
- **After**: Maarten compiles a `.ink` using an unsupported construct and immediately
  gets a clear error naming the construct and its source location — no story produced.
- **Decision enabled**: he can fix or redesign the construct on the spot, confident
  nothing unsupported ever slips through silently.

#### Problem
Maarten, out of habit from full Ink, sometimes reaches for a `LIST`, a thread, or a
`{a|b|c}` sequence. He needs the compiler to catch these loudly — naming the
construct and where it is — rather than emitting a silently-wrong story.

#### Who
- Swift app/game developer | accustomed to full Ink | needs guardrails against unsupported constructs.

#### Solution
Detect each unsupported construct (rows 25-28, 36-39) during compilation; stop;
produce no story; emit an error naming the construct and its source location, ideally
pointing to the feature reference (US-07).

#### Domain Examples
1. **LIST** — `LIST colours = red, green, blue` -> error "LIST declarations are not
   supported (line 12)"; no story produced.
2. **Variable-text sequence** — `{red|green|blue}` -> error "variable-text sequence is
   not supported (line 8)".
3. **External function** — `EXTERNAL roll_dice()` -> error "external function is not
   supported (line 3)".

#### UAT Scenarios (BDD)
```gherkin
Scenario: A variable-text sequence is rejected with a named, located error
  Given a .ink source using a variable-text sequence "{a|b|c}"
  When Maarten compiles it through the in-process compile entry point
  Then compilation stops without producing a story
  And the error names "variable-text sequence" as unsupported
  And the error reports the source location of the construct

Scenario: A LIST declaration is rejected with a named, located error
  Given a .ink source containing a "LIST" declaration
  When the source is compiled
  Then compilation stops without producing a story
  And the error names "LIST" as unsupported with its source location

Scenario: A thread is rejected with a named, located error
  Given a .ink source using a thread "<- knot"
  When the source is compiled
  Then compilation stops without producing a story
  And the error names "thread" as unsupported with its source location

Scenario: An external function is rejected with a named, located error
  Given a .ink source declaring an EXTERNAL function
  When the source is compiled
  Then compilation stops without producing a story
  And the error names "external function" as unsupported with its source location

Scenario: No unsupported construct ever compiles silently
  Given a corpus of .ink sources each using one unsupported construct
  When each is compiled
  Then every one stops with an error naming the construct — none produce a story
```

#### Acceptance Criteria
- [ ] Each unsupported construct (rows 25-28, 36-39) is detected and stops compilation.
- [ ] No story is produced when an unsupported construct is present.
- [ ] The error names the unsupported construct.
- [ ] The error reports the construct's source location.
- [ ] No unsupported construct ever compiles to silent output (corpus-level guarantee).

#### Outcome KPIs
- **Who**: a developer who used an unsupported construct.
- **Does what**: receives a clear located error instead of a broken story.
- **By how much**: 100% of unsupported constructs in the corpus rejected with a named, located error; 0% silent wrong output.
- **Measured by**: an unsupported-construct corpus test asserting error + location per construct.
- **Baseline**: today the native path cannot compile at all; the silent-failure risk is the thing this story eliminates.

#### Technical Notes
- Detection mechanism is independent of supported-feature slices; **recommended to
  land alongside US-02** so unsupported input never silently slips through during
  US-02..US-05 development. Multi-diagnostic recovery is a future enhancement (out of scope).

---

### US-07: Publish the supported/unsupported feature reference

#### Elevator Pitch
- **Before**: the author has no single place to learn which Ink features will compile,
  so discovers unsupported ones by trial and error (failed compiles).
- **After**: Maarten (or Raya) opens one reference document and sees every construct
  marked supported or rejected, with an example and reason.
- **Decision enabled**: he can author within the supported set deliberately, choosing
  supported alternatives before writing a line.

#### Problem
The user explicitly asked for "a clear description of the Ink features that are and
are not supported." Without it, authors guess, and the first signal of an
unsupported feature is a failed compile (or, worse, a wrong story).

#### Who
- Swift app/game developer and story author | planning a story | wants to stay in bounds up front.

#### Solution
A reference document listing every Ink construct as MUST-COMPILE or MUST-REJECT,
each with a one-line example and reason, derived from the runtime's Feature
Coverage Matrix; its statuses match actual compiler behaviour.

#### Domain Examples
1. **Supported lookup** — author checks "tunnels", sees supported, example
   `-> detour ->`, reason "runtime supports tunnels (row 34)".
2. **Rejected lookup** — author checks "LIST", sees rejected, example
   `LIST x = a, b`, reason "runtime has no list support (row 37)".
3. **Stay-in-bounds** — seeing `shuffle` is rejected, the author picks a
   variable-driven alternative instead of a `{~a|b}` sequence.

#### UAT Scenarios (BDD)
```gherkin
Scenario: The reference lists every supported construct with an example
  Given the supported/unsupported feature reference document
  When an author looks up a supported construct (e.g. tunnels)
  Then the document shows it as supported with a one-line example and reason

Scenario: The reference lists every unsupported construct with an example
  Given the reference document
  When an author looks up an unsupported construct (e.g. LIST)
  Then the document shows it as rejected with a one-line example and reason

Scenario: The reference matches actual compiler behaviour
  Given the reference document and the compiler
  When any construct's documented status is checked against the compiler
  Then the documented status matches what the compiler does for that construct
```

#### Acceptance Criteria
- [ ] Every supported construct (rows 1-35) is listed with example + reason.
- [ ] Every unsupported construct (rows 25-28, 36-39) is listed with example + reason.
- [ ] The document states the supported set == the runtime's playable set.
- [ ] Documented statuses match actual compiler behaviour.

#### Outcome KPIs
- **Who**: an author planning a story.
- **Does what**: predicts compile/reject from the reference before authoring.
- **By how much**: an author can correctly predict compile vs reject for any listed construct (100% of constructs documented; statuses match compiler).
- **Measured by**: a doc-vs-compiler consistency check over the construct list.
- **Baseline**: no such reference exists today.

#### Technical Notes
- Reference (DIVIO/Diataxis) document, not a tutorial. Draft early as a living
  artifact; finalise after US-02..US-06 so it reflects shipped reality.

---

## Wave: DISCUSS / [REF] Outcome KPIs (feature-level)

### Objective
Make the entire Ink toolchain pure-Swift end to end: supported stories compile
in-process and play identically to inklecate, and unsupported features fail loud.

### Outcome KPIs

| # | Who | Does What | By How Much | Baseline | Measured By | Type |
|---|-----|-----------|-------------|----------|-------------|------|
| 1 | Developer with a supported story | compiles + plays it in-process, oracle-identical | 100% of supported-corpus stories play line-for-line identical to inklecate | 0% (inklecate required) | execution-equivalence oracle test suite | Leading |
| 2 | Developer using an unsupported construct | gets a clear located error, not a broken story | 100% rejected with named+located error; 0% silent wrong output | n/a (native path absent today) | unsupported-construct corpus test | Leading |
| 3 | Author planning a story | predicts compile/reject from the reference | 100% of constructs documented; statuses match compiler | no reference exists | doc-vs-compiler consistency check | Leading |
| 4 | Developer's build | compiles supported stories without inklecate | 0 inklecate invocations for supported stories | every build invokes inklecate | build-process check (no inklecate subprocess) | Leading |

### Metric Hierarchy
- **North Star**: % of supported-corpus stories that compile in-process and play
  line-for-line identical to the inklecate oracle (target 100%).
- **Leading indicators**: per-tier oracle-equivalence pass rate (S1..S4); unsupported-
  construct rejection coverage; doc-vs-compiler consistency.
- **Guardrail metrics**: zero silent wrong output on unsupported input (must never
  regress); frozen InkSwift module untouched; no new runtime dependencies introduced.

### Measurement Plan
| KPI | Data Source | Collection Method | Frequency | Owner |
|-----|------------|-------------------|-----------|-------|
| Oracle equivalence | inklecate + runtime | execution-equivalence test suite | per CI run | crafter / acceptance-designer |
| Rejection coverage | unsupported corpus | corpus test asserting error+location | per CI run | acceptance-designer |
| Doc consistency | reference doc + compiler | consistency check | per CI run + on doc edit | nw-product-owner / documentarist |
| No-inklecate build | build process | subprocess check | per CI run | platform-architect |

### Hypothesis
We believe that an in-process native Swift compiler bounded to the runtime's
supported set, with loud rejection of unsupported features, for Maarten (and Raya)
will achieve a fully pure-Swift Ink toolchain. We will know this is true when
supported-corpus stories play 100% identical to the inklecate oracle and 0%
of unsupported constructs produce silent wrong output.

---

## Wave: DISCUSS / [REF] Driving Ports (conceptual)

DISCUSS names these conceptually; DESIGN defines their shape.
- **Compile entry point** — accepts `.ink` source (file or string) and yields either
  a runnable story (supported) or a clear, located error (unsupported / invalid).
- **(Secondary) JSON emit** — optional path yielding the Ink JSON representation for
  oracle structural comparison and caching/interop.

---

## Wave: DISCUSS / [REF] Pre-requisites

- SwiftInkRuntime (`Story`) — delivered; provides the runnable-story input contract.
- inklecate at `/Users/Maarten.Engels/.local/bin/inklecate` — the oracle (available).
- Reference C# compiler at `/Users/Maarten.Engels/Downloads/ink/compiler/` — DESIGN reference.
- Ink JSON format spec (`docs/ink_JSON_runtime_format.md` + JsonSerialisation.cs) — for secondary JSON output.

---

## Wave: DISCUSS / [REF] Out of Scope (recorded)

- Compiling Ink features the runtime does not support (variable-text sequences/
  cycles/once/shuffle, threads, LIST, RANDOM/SEED_RANDOM, externals) — these are
  rejected with errors (US-06), not compiled.
- Any change to the frozen `InkSwift` (JS-bridge) module.
- DESIGN-level concerns: parser implementation (hand-rolled vs swift-parsing), type/
  module structure, access modifiers, the runnable-story output type shape.
- Multi-diagnostic error recovery (report many errors in one pass) — future enhancement.
- Full-Ink ambitions beyond the runtime's ceiling (lists, threads, etc.).

---

## Wave: DISCUSS / [REF] Risks (surfaced, not managed)

| Risk | Prob | Impact | Mitigation (for DESIGN) |
|---|---|---|---|
| Weave resolution correctness (S3/US-04) | High | High | Research-flagged highest risk; DESIGN spike on weave before committing the slice plan; oracle tests per weave edge case. |
| Silent divergence from oracle | Medium | High | Execution-equivalence oracle as the primary correctness gate on every supported slice. |
| Scope drift (compiler accepts > runtime plays) | Medium | High | Compiler accepted set bound to the runtime matrix; consistency check in shared-artifacts registry. |
| CONST inlining / choice-flag encoding omitted (D6) | Medium | High | Named compile-time obligations; oracle tests in S2/S3 would fail if skipped. |
| Slice S3/S4 oversize | Medium | Medium | Splitting guidance recorded in each slice brief; re-slice before build if >1 day. |

---

## Wave: DISCUSS / [REF] Wave Decisions Summary

- **Scope Assessment: PASS** — 7 slices (S0-S6), one bounded context, one integration
  contract; S3/S4 flagged for further splitting; bounded to runtime scope.
- **New job validated and registered**: job-native-compilation (Maarten), related to
  job-story-playback.
- **Persona created**: `docs/product/personas/maarten.md`.
- **SSOT updated**: `jobs.yaml` (+job), `journeys/story-author.yaml` (+native-compilation journey).
- **8 locked decisions** (D1-D8) recorded above.
- **DIVERGE artifacts**: none present for this feature — JTBD run fresh this wave;
  recorded as a minor risk (no prior validated direction doc), mitigated by the
  thorough feasibility research already in hand.
- **DoR**: validated below (9 items) before handoff.

---

## Wave: DISCUSS / [REF] Definition of Ready Validation

Applied per story (US-01..US-07). All stories share the same structure; the table
below reports the consolidated result with per-story notes where they differ.

| DoR Item | Status | Evidence |
|----------|--------|----------|
| 1. Problem statement clear, domain language | PASS | Each story opens with a Maarten-grounded problem in Ink/toolchain domain language (e.g. US-03 CONST inlining; US-06 unsupported-habit). |
| 2. User/persona with specific characteristics | PASS | Maarten persona file created (toolchain owner, already adopted native runtime, habituated to inklecate). Each story's "Who" narrows the context. |
| 3. 3+ domain examples with real data | PASS | Each story has 3 examples with concrete Ink (`Hello, world.`, `VAR score = 3`, `{double(5)}`, `LIST colours = red,green,blue`, `raise(ref score)`). |
| 4. UAT in Given/When/Then (3-7 scenarios) | PASS | US-01:3, US-02:3, US-03:3, US-04:4, US-05:4, US-06:5, US-07:3 — all within 3-7. |
| 5. AC derived from UAT | PASS | Each story's AC checklist maps to its scenarios. |
| 6. Right-sized (1-3 days, 3-7 scenarios) | PASS (with split flags) | US-01/02/06/07 clearly ≤1-2 days. US-03/04/05 carry explicit split guidance (a/b/c) if >1 day — sizing risk surfaced, not hidden. |
| 7. Technical notes: constraints/dependencies | PASS | Each story records dependencies (US-N depends on US-(N-1)), compile-time obligations (D6), the frozen-module constraint (D8), and the weave risk (US-04). |
| 8. Dependencies resolved or tracked | PASS | Runtime (delivered), inklecate oracle (available), C# reference (available) all confirmed. Inter-story order tracked in the story map priority rationale. |
| 9. Outcome KPIs defined with measurable targets | PASS | Each story + the feature level define Who/Does-what/By-how-much/Measured-by/Baseline with numeric targets (100% oracle identity; 0% silent output). |

### DoR Status: PASSED

---

## Wave: DISCUSS / [REF] Peer Review Result

**Verdict: APPROVED** (nw-product-owner-reviewer, iteration 1). DoR 9/9; JTBD
traceability complete (all 7 stories trace to job-native-compilation); slice
composition pass (every slice has a user-visible story); journey coherence pass
(happy + sad paths, 5 shared artifacts single-sourced); 0 anti-patterns;
0 critical, 0 high issues.

**One medium issue, carried to DESIGN (non-blocking):**
- The "supported-corpus" referenced by Feature KPI #1 is not enumerated in DISCUSS.
  Acceptable here (measurement method and intent are clear: canonical Ink stories
  up to The Intercept ceiling). **DESIGN action**: enumerate the corpus explicitly —
  base fixtures per slice (S1 linear, S2 variables, S3 choices, S4 ceiling) plus
  The Intercept as the comprehensive end-to-end oracle test — and document the
  doc-vs-compiler consistency-check procedure for US-07.

---

## Wave: DISCUSS / [REF] Open Questions for DESIGN

1. **Parser strategy** — hand-rolled (research-recommended, closest to the C#
   mental model) vs swift-parsing (Point-Free). Implementation choice; deferred.
2. **Weave-resolution spike** — the feasibility study names this the single
   highest-risk algorithm (S3/US-04). Recommend a spike before committing the S3
   slice plan.
3. **Runnable-story output shape** — the exact in-memory structure handed to the
   runtime (the integration contract). The runtime owns the contract; DESIGN
   confirms whether the compiler targets the existing decoder's node tree directly
   or emits JSON that the existing decoder consumes.
4. **Secondary JSON output** — when/whether to emit it; container-naming
   normalisation needed for Level-2 structural oracle comparison.
5. **Error model** — single-error-then-stop (DISCUSS scope) vs future
   multi-diagnostic recovery; DESIGN sets the error-reporting structure.
6. **Test corpus enumeration** — per the peer-review medium finding above.
7. **CONST inlining + choice-flag/invisible-default encoding** — confirm the
   compiler-side implementation of these compile-time obligations (D6) against
   inklecate's actual output before codegen.

---

# Feature Delta: native-ink-compiler (DESIGN wave)

**Wave**: DESIGN | **Architect**: Morgan (nw-solution-architect) | **Date**: 2026-06-14
**Mode**: PROPOSE | **Density**: lean (Tier-1 [REF] sections)
**Status**: DESIGN sections appended below; ADRs 006-009 PROPOSED pending user
confirmation of the four decisive forks (see `design/wave-decisions.md`).

> DESIGN names types/signatures where needed to express the integration contract
> (the DESIGN/DISCUSS split); it does not include implementation bodies.

---

## Wave: DESIGN / [REF] Decisions (DDD)

| # | Decision | Locked by |
|---|---|---|
| DDD-1 | Compiler is co-located as a new `Compiler/` layer **inside** the `SwiftInkRuntime` module. It constructs internal `ContainerNode`/`NodeKind` directly. (ADR-006 Option A.) | ADR-006 |
| DDD-2 | Primary output (D3, no JSON round-trip) is delivered via a new **internal** `StoryBlueprint(root: ContainerNode)` init; the public `StoryBlueprint(json:)` is untouched. | ADR-006 |
| DDD-3 | Secondary JSON emit (D4) is an optional codegen sink writing an Ink-JSON string (via `JSONEncoder`/string building in `Compiler/`, NOT `JSONSerialization` — R3 holds). It doubles as the Level-2 structural-oracle artifact. | ADR-006 |
| DDD-4 | New boundary rule **R5** governs `Compiler/`: may import `Decoder/` node types; may NOT import `Engine/`; may NOT call `JSONSerialization`; `Decoder/`/`Engine/`/`Facade/` may NOT import `Compiler/` except the single facade compile entry point. SwiftLint-enforced. | ADR-006 |
| DDD-5 | Parser is **hand-rolled** recursive-descent/combinator port of C# `StringParser` (no new dependency; closest C# mapping). Pratt sub-parser for expressions. | ADR-007 |
| DDD-6 | **Weave-resolution spike gates the S3 slice plan.** S3 sizing is not committed until the spike passes oracle line/choice identity on a representative corpus (flat, nested, labeled-gather, sealed-weave). | ADR-008 |
| DDD-7 | **Single-error-then-stop, located** error model. Compile yields a runnable story OR one structured `CompileError(kind, message-naming-construct, line/column)`. Multi-diagnostic recovery out of scope. | ADR-009 |
| DDD-8 | Unsupported-construct detection (rows 25-28, 36-39) is a reject-list independent of supported-feature codegen; lands alongside S1 so nothing slips through silently during S1-S5. | ADR-009 |
| DDD-9 | Compile-time obligations D6 (CONST inlining; choice-flag/invisible-default encoding) live in the **codegen** stage and are validated by the S2 (CONST) and S3 (choice-flag) oracle tests — their omission surfaces as an oracle failure. | D6; ADR-008 |
| DDD-10 | Driving port: a public compile entry point accepting `.ink` source (string or file URL), yielding `StoryBlueprint` or throwing `CompileError`. Secondary: JSON emit. Driven ports: filesystem read (INCLUDE/source); inklecate oracle is **test-only**. | ADR-006/009 |
| DDD-11 | Swift tools version reconciled to **5.8+** (brief) — Package.swift `swift-tools-version` raised from 5.6 to 5.8 when the compiler target lands. No new product dependency. | Tech stack |
| DDD-12 | Compiler accepted set == runtime supported set (matrix rows 1-35). Accepting more = silent breakage; forbidden (D1). | D1 |

---

## Wave: DESIGN / [REF] Reuse Analysis (HARD GATE)

Searched the codebase for components with overlapping responsibility before
designing any new component. Default decision is EXTEND/REUSE; every CREATE NEW
cites why extending is impossible or unacceptable coupling.

| Existing Component | File | Overlap | Decision | Justification |
|---|---|---|---|---|
| `ContainerNode` | `Decoder/ContainerNode.swift` | The compiler's codegen target IS this node tree | **REUSE AS-IS** | Codegen constructs `ContainerNode` values directly (co-located, ADR-006). No new node model; the runtime consumes the compiler's output through the identical type it consumes from `InkDecoder`. |
| `NodeKind` | `Decoder/NodeKind.swift` | Every runtime instruction the codegen emits | **REUSE AS-IS** | Codegen emits existing `NodeKind` cases (`.text`, `.divert`, `.choicePoint`, `.variableAssignment`, `.tunnelDivert`, `.variablePointer`, …). The supported set (rows 1-35) maps onto cases already present. R2 preserved — co-location means no `public` needed. |
| `StoryBlueprint` | `Facade/StoryBlueprint.swift` | Construction contract handed to `Story` | **EXTEND** | Add one **internal** `init(root: ContainerNode)` for the no-JSON D3 path. Public `init(json:)` untouched. Minimal additive change to a `Facade/` type; no new public surface beyond the compile entry point. |
| `Story` | `Facade/Story.swift` | Public construction + facade for the runnable story | **EXTEND** | Add a public compile entry point (a convenience `init(inkSource:) throws` and/or delegate to `InkCompiler.compile`). Follows the established `init(json:)`/delegation pattern. `StoryError` may gain a `compileError` bridge case if compile is surfaced via `Story`. |
| `InkDecoder` | `Decoder/InkDecoder.swift` | Turns structured data into the node tree (the "structured → node tree" stage the compiler's codegen mirrors) | **REUSE AS-IS (no change) for the primary path; REUSE for the optional JSON-roundtrip / Option-C fallback** | The decoder is the JSON→tree path; the compiler's codegen is the AST→tree path producing the **same** `ContainerNode`. They converge on one consumer. If the user overrides to ADR-006 Option C, the decoder becomes the primary consumer of the compiler's JSON unchanged. The compiler does NOT share decode logic (different input: AST vs JSON), but shares the **output contract**. |
| `InkDecoder.probe()` | `Decoder/InkDecoder.swift` | Earned-Trust startup probe for the JSON/filesystem substrate | **EXTEND (pattern)** | The compiler's filesystem driven adapter (source/INCLUDE read) gets its own `probe()` per principle 13: verify it can read a known fixture from the configured root before compiling. Mirrors the existing decoder-probe-at-startup pattern. |
| Oracle test harness | `Tests/SwiftInkRuntimeTests/Acceptance/Milestone5b_*.swift` + others | inklecate/JS-bridge as correctness oracle; committed `.ink.json` fixtures; `#if os(macOS) import InkSwift` | **REUSE / EXTEND** | The existing pattern (pre-compile fixtures offline via inklecate, commit `.ink.json`, compare via `@testable import` + `InkSwift` oracle on macOS, REGEN env-gate) is exactly the compiler oracle harness. New compiler tests add `.ink` source corpus fixtures and an execution-equivalence comparator; no new harness architecture. |
| Existing `.ink`/`.ink.json` fixtures | `Tests/SwiftInkRuntimeTests/*.ink(.json)`, `TheIntercept.ink` | Test corpus | **REUSE / EXTEND** | `TheIntercept.ink` is the comprehensive end-to-end oracle for the supported ceiling. Existing per-slice `.ink` sources are reused as supported-corpus fixtures; new fixtures are added per the corpus enumeration below. |
| `ChoiceFlags` | `Decoder/NodeKind.swift` (type) | Choice-flag bitfield the codegen must emit (row 10, D6) | **REUSE AS-IS** | The codegen emits `ChoiceFlags` values onto `.choicePoint`; the same flag semantics the runtime already reads. No new flag model. |

**CREATE NEW components** (all are genuinely new responsibilities with no existing
analog — the compiler is a new bounded responsibility; extending is not possible
because no compilation stage exists today):

| New Component | Path | Why no existing component can be extended |
|---|---|---|
| `CommentEliminator` | `Compiler/Lexer/CommentEliminator.swift` | No comment-stripping stage exists; runtime consumes already-compiled JSON. |
| Parser combinator core + `InkParser` | `Compiler/Parser/` | No `.ink`-source parser exists anywhere in the codebase (runtime parses JSON, not Ink). |
| AST node types | `Compiler/AST/` | The runtime's `ContainerNode` is the *runtime* tree, not the *parsed* Ink AST (which carries source positions, unresolved symbolic paths, weave structure). A distinct, transient AST is required before codegen. |
| Codegen / runtime-object emitter | `Compiler/Codegen/` | No AST→`ContainerNode` translation exists; this is the new core. Reuses `ContainerNode`/`NodeKind` as its *output*, but the translation logic is new. |
| `CompileError` + error reporter | `Compiler/Error/` | `StoryError` is the runtime error taxonomy (decode/choice/state); compile errors (located, construct-named, syntax) are a distinct domain (ADR-009). |
| `InkCompiler` (compile entry façade) | `Compiler/InkCompiler.swift` | The new driving port; no compile entry point exists. |
| Optional JSON emitter | `Compiler/Codegen/JSONEmitter.swift` | Secondary D4 sink; no Ink-JSON *writer* exists (decoder only reads). |
| Source/INCLUDE filesystem adapter + `probe()` | `Compiler/IO/` | Driven adapter for reading `.ink` source and INCLUDE files with an Earned-Trust probe; the decoder's bundle read is a different concern (fixed test fixture, not arbitrary source). |

Outcome: **CREATE NEW is confined to the genuinely-new compiler pipeline; every
runtime integration point (node tree, blueprint, story, decoder, oracle harness,
fixtures, choice flags) is REUSE or minimal EXTEND.** Zero unjustified CREATE NEW.

---

## Wave: DESIGN / [REF] Component Decomposition

Maps the C# stages (CommentEliminator → StringParser/combinators → InkParser →
typed AST / ParsedHierarchy with GenerateRuntimeObject → ContainerNode tree
[+ optional JSON]) onto Swift components, honoring ADR-006 module placement.

| Component | Path | Change | C# analog | Responsibility |
|---|---|---|---|---|
| `CommentEliminator` | `Sources/SwiftInkRuntime/Compiler/Lexer/CommentEliminator.swift` | NEW | `CommentEliminator.cs` | Pre-pass: strip `//` and `/* */`, comment-in-string aware. |
| Combinator core | `Sources/SwiftInkRuntime/Compiler/Parser/StringParser.swift` | NEW | `StringParser.cs` | Cursor + rule-state stack + line/col tracking + combinators (`OneOf`, `OneOrMore`, `Optional`, `Peek`, `ParseUntil`). |
| `InkParser` | `Sources/SwiftInkRuntime/Compiler/Parser/InkParser*.swift` | NEW | 17 `InkParser_*.cs` partials | Statement-level rules (knot/stitch/divert/choice/gather/logic/conditional/tag); Pratt expression sub-parser. |
| AST node types | `Sources/SwiftInkRuntime/Compiler/AST/*.swift` | NEW | `ParsedHierarchy/*.cs` | Typed parsed Ink AST carrying source positions + unresolved symbolic paths + weave structure. |
| Weave resolver | `Sources/SwiftInkRuntime/Compiler/Codegen/WeaveResolver.swift` | NEW (spike-gated, DDD-6) | `Weave.cs` | Indentation→hierarchy; loose-end propagation; gather divert stitching; sealed/open. |
| Codegen (runtime-object emitter) | `Sources/SwiftInkRuntime/Compiler/Codegen/RuntimeObjectEmitter.swift` | NEW | `GenerateRuntimeObject()` per node | AST → `ContainerNode`/`NodeKind` tree. Performs D6 obligations (CONST inlining, choice-flag/invisible-default encoding). Reference resolution + container flattening. |
| `CompileError` + reporter | `Sources/SwiftInkRuntime/Compiler/Error/CompileError.swift` | NEW | `Expect()` diagnostics | Located, construct-named single error (ADR-009); reject-list for unsupported constructs. |
| JSON emitter (optional) | `Sources/SwiftInkRuntime/Compiler/Codegen/JSONEmitter.swift` | NEW | `JsonSerialisation.WriteRuntimeObject` | Secondary D4 Ink-JSON string sink; Level-2 oracle artifact. |
| Source/INCLUDE IO adapter | `Sources/SwiftInkRuntime/Compiler/IO/SourceReader.swift` | NEW | `InkParser_Include.cs` IO | Driven adapter: read `.ink` source + INCLUDE files; `probe()` (Earned Trust). |
| `InkCompiler` | `Sources/SwiftInkRuntime/Compiler/InkCompiler.swift` | NEW | `Compiler.cs` entry | Driving port: `compile(source:) throws -> StoryBlueprint`; optional `emitJSON(source:)`. |
| `StoryBlueprint` | `Sources/SwiftInkRuntime/Facade/StoryBlueprint.swift` | EXTEND | — | + internal `init(root: ContainerNode)` (no-JSON D3 path). |
| `Story` | `Sources/SwiftInkRuntime/Facade/Story.swift` | EXTEND | — | + public compile entry (`init(inkSource:) throws` or delegate). |

---

## Wave: DESIGN / [REF] Driving and Driven Ports

**Driving ports (inbound):**
- **Compile entry point** — `InkCompiler.compile(source: String) throws -> StoryBlueprint` (and a file-URL overload). Yields a runnable story (via `StoryBlueprint(root:)`) or throws `CompileError` (located, construct-named). Surfaced publicly, optionally also as `Story.init(inkSource:) throws`.
- **(Secondary) JSON emit** — `InkCompiler.emitJSON(source:) throws -> String`. Optional Ink-JSON output for oracle structural comparison, caching, interop (D4).

**Driven ports (outbound) + adapters:**
- **Source/INCLUDE filesystem read** — `SourceReading` port; adapter `SourceReader` (Foundation `Data(contentsOf:)`). Carries a `probe()` (Earned Trust): verify the configured source root is readable and a known fixture round-trips before compiling. Capability-injected with the source root, not a god-object filesystem.
- **inklecate oracle — TEST-ONLY** — NOT a production port. Used offline to pre-compile fixtures (`.ink.json`) and (on macOS) the `InkSwift` JS bridge is the execution oracle, exactly as the existing harness does. Never invoked from production code or per-CI-run compilation.

---

## Wave: DESIGN / [REF] Test Corpus Enumeration (closes peer-review medium finding)

**Supported corpus (execution-equivalence, Level-1):**
| Slice | Fixture(s) | Exercises |
|---|---|---|
| S0 | `compile-skeleton-hello.ink` | one line plain text; empty source; trailing newline (US-01 examples). |
| S1 | `compile-linear-flow.ink` | knots, stitch, absolute + relative `.^` + anchor diverts, glue (rows 1-5,15). |
| S2 | `compile-variables.ink` | VAR/temp/CONST(+inlining), assignment, `{score}` read, `{2+3*4}`, string interp (rows 16-21,31). |
| S3 | weave spike corpus: `compile-weave-flat.ink`, `compile-weave-nested.ink`, `compile-weave-labeled-gather.ink`, `compile-weave-sealed.ink` | plain/bracketed/sticky/conditional choices, gathers + labels, read counts, choice-flag/invisible-default encoding (rows 6-14). |
| S4 | `compile-ceiling.ink` | inline/block/switch conditionals, functions + inline calls, tunnels, ref params, tags (rows 22-24,29-35). |
| End-to-end | `TheIntercept.ink` (existing) | the comprehensive supported-ceiling oracle (compile natively, play, compare to inklecate/JS-bridge line-for-line). |

**Unsupported corpus (one construct per fixture, US-06 — asserts named+located error, no story):**
`reject-seq.ink` `{a|b|c}`; `reject-cycle.ink` `{&a|b}`; `reject-once.ink` `{!a|b}`;
`reject-shuffle.ink` `{~a|b}`; `reject-thread.ink` `<- knot`; `reject-list.ink` `LIST x = a,b`;
`reject-random.ink` `RANDOM(1,6)` / `SEED_RANDOM(...)`; `reject-external.ink` `EXTERNAL f()` (rows 25-28,36-39).

**Doc-vs-compiler consistency check (US-07):** a test iterates the supported/unsupported
reference document's construct list and asserts each documented status matches actual
compiler behaviour (compiles vs rejects), closing the reference↔reject-list gap.

---

## Wave: DESIGN / [REF] Technology Stack

| Component | Choice | Version | License | Rationale |
|---|---|---|---|---|
| Swift tools | SPM | 5.8+ (raise from 5.6) | Apache 2.0 | Reconciles Package.swift (5.6) with brief (5.8+); DDD-11. |
| Foundation | bundled | — | Apple APSL | `Data`, string APIs; the only runtime dependency. No `JSONSerialization` in `Compiler/` (R3). |
| Parser | hand-rolled combinator | — | (in-repo) | ADR-007; no new dependency (guardrail). |
| Secondary JSON writer | `JSONEncoder`/string building | bundled | Apple APSL | D4 sink; not `JSONSerialization` parsing (R3). |
| Swift Testing / XCTest | bundled | — | Apple | Oracle + corpus tests; reuse existing harness. |
| inklecate | `/Users/Maarten.Engels/.local/bin/inklecate` | pinned | MIT | TEST-ONLY oracle; offline fixture generation (REGEN-gated). |
| SwiftLint | dev tool | 0.55+ | MIT | Enforces R1/R3 **and new R5** (Compiler/ dependency direction). |

No new product/runtime dependency. Guardrail "no new runtime dependencies" holds.

---

## Wave: DESIGN / [REF] Open Questions Deferred to DISTILL/DELIVER

1. **Container-naming normalisation for Level-2 structural JSON comparison** — internal counters (`c-0`, `g-0`) must agree for structural diff; the normalisation procedure is a DISTILL/test-design concern (Level-1 execution-equivalence is the primary gate and is naming-agnostic).
2. **S3 a/b/c split sizing** — finalised only after the ADR-008 weave spike passes (open-weave-first fallback if the spike escalates).
3. **S2 a/b split** (VAR/temp/read vs operators+CONST) — crafter-level sizing call during DELIVER if S2 exceeds a day.
4. **Public compile-entry surface shape** — whether the public entry is `InkCompiler.compile` only, or also a `Story.init(inkSource:)` convenience — a small API-ergonomics decision for DISTILL/acceptance-design.
5. **Exact `CompileError` case enumeration** — kinds beyond `unsupportedConstruct`/`syntaxError`/`unresolvedReference` discovered during DELIVER RED against real parser failures.

---

## Wave: DESIGN / [REF] Back-Propagation to DISCUSS

DESIGN resolves DISCUSS Open Questions #1-#7 without contradicting any locked
DISCUSS assumption (D1-D8). No DISCUSS decision is reversed:
- D3 (no JSON round-trip) is honored literally by ADR-006 Option A (recommended).
  IF the user overrides to Option C, D3 is re-characterised as "logically
  in-process (in-memory JSON round-trip, no external binary)" — that override
  would add a `## Changed Assumptions` entry here. As of this writing the
  recommendation preserves D3 verbatim, so **no Changed Assumptions and no
  `design/upstream-changes.md` are required.** No user stories or AC change.

---

# Feature Delta: native-ink-compiler (DEVOPS wave)

**Wave**: DEVOPS | **Architect**: Apex (nw-platform-architect) | **Date**: 2026-06-14
**Density**: lean (Tier-1 [REF]) | **Status**: DEVOPS sections appended below.

> **Framing**: native-ink-compiler ships as part of the InkSwift **SPM library**.
> There is NO cloud/k8s/server deployment, NO runtime telemetry, NO blue-green/
> canary rollout. "Deployment" = SPM library versioning; "observability" = CI
> test-gate metrics. The cloud-native DEVOPS surface is **N/A** and is marked so.

---

## Wave: DEVOPS / [REF] Required Reading Checklist

- ✓ `feature-delta.md` DISCUSS Outcome KPIs (feature-level table) + DESIGN sections (Reuse, R5, Test Corpus, Ports, Tech Stack)
- ✓ `design/wave-decisions.md` (DESIGN summary)
- ✓ `docs/product/architecture/brief.md` — native-ink-compiler subsection (R5, `Compiler/` layout, C4 deltas, enforcement), Paradigm/Boundary Rules R1/R2/R3, Tech Stack (SwiftLint 0.55+, Swift 5.6 → 5.8)
- ✓ ADR-006 (R5 via SwiftLint custom_rules), ADR-008 (weave spike gate — DELIVER-time), ADR-009 (error model)
- ✓ `.forgejo/workflows/tests.yml`, `Package.swift`, confirmed no `.swiftlint.yml` existed

---

## Wave: DEVOPS / [REF] Environment Matrix

| Environment | Platform | Oracle | Runs | Precondition |
|---|---|---|---|---|
| `clean` | macos, linux | committed inklecate `.ink.json` fixtures | `swift build` + **execution-equivalence KPI #1** (native compile vs committed `.ink.json`, hermetic) + rejection (KPI #2) + doc-consistency (KPI #3) + no-inklecate guardrail (KPI #4) | Swift ≥ 5.8; no JS-bridge needed |
| `with-oracle-macos` | macos | InkSwift JS-bridge | all of `clean` **plus** the SECONDARY JS-bridge ground-truth cross-check for KPI #1. The macos-arm64 CI host. | InkSwift/JXKit builds; committed `.ink.json` fixtures present |
| `with-inklecate-local` | macos, linux | inklecate (offline) | REGEN-gated `.ink.json` fixture (re)generation only | inklecate on PATH; REGEN flag set |

inklecate is **test-only/offline** (fixture provenance); CI consumes committed fixtures, never inklecate. **[DISTILL UI-1 reconciliation, 2026-06-14]**: KPI #1's core comparison imports no `InkSwift`, so it is hermetic and runs cross-platform on `clean` (the original matrix scoped it to `with-oracle-macos`); the JS-bridge is now the secondary cross-check. Machine artifact: `environments.yaml`.

---

## Wave: DEVOPS / [REF] CI/CD Pipeline Outline

**Platform**: Forgejo Actions, extending `.forgejo/workflows/tests.yml` (a `macOS` test job on `macos-arm64` + a live `lint` job). The macos-arm64 host runs the full suite incl. the secondary JS-bridge cross-check; the hermetic KPI #1/#2/#3/#4 gates are themselves cross-platform (UI-1).

**Trigger rules (Trunk-Based)**: `on: push` + `on: pull_request` — every push and PR to `main` and short-lived slice branches runs the full job (main always releasable).

**Stage list (Tier-1 outline)** — commit stage only; no acceptance/capacity/production stages apply to a library:

1. `checkout`
2. **`lint` (boundary gate, R1/R3/R5)** — `swiftlint lint --strict --config .swiftlint.yml`. **[DISTILL UI-2 reconciliation, 2026-06-14]**: this `lint` job is **already LIVE** in `.forgejo/workflows/tests.yml` (landed in merge `a2fa4ac`), with a brew-install availability step. It passes on the current tree; the R5 `custom_rules` are path-scoped to `Compiler/` and so activate automatically as those files land. (The original D2 plan deferred activation to the first `Compiler/` slice; reality landed it early and green.)
3. `build` — `swift build` (raise tools to 5.8 when `Compiler/` lands).
4. `test` — `swift test` (existing runtime suite + new compiler tests; execution-equivalence KPI #1 runs here — hermetic, cross-platform).
5. **`no-inklecate guardrail` (KPI #4)** — source guard (production `Compiler/` references no `Process`/inklecate) + a test asserting no inklecate subprocess is spawned during native compile. *Activation*: with first `Compiler/` slice.

> **`tests.yml` status**: the `lint` job is live (UI-2). The `no-inklecate` guard test ships with the DISTILL suite (`Compiler_NoInklecateGuardrailTests`) and runs inside the existing test job.

**Quality-gate taxonomy** (per shift-left): local pre-commit/pre-push (optional, mirror `swiftlint` + `swift test`) → PR status checks (the `test-macos` job is the required check) → CI commit stage (lint/build/test/guardrail above). No deploy/canary/production gates (library).

---

## Wave: DEVOPS / [REF] Monitoring Contracts (KPI → CI instrument)

There is no runtime telemetry; each KPI is a CI gate (a test assertion). SSOT: `docs/product/kpi-contracts.yaml`.

| KPI | Outcome | CI Instrument | Pass Threshold | Guardrail Semantics |
|---|---|---|---|---|
| **#1** Oracle execution-equivalence | supported story compiles + plays oracle-identical | execution-equivalence oracle suite (per-slice + `TheIntercept` e2e): native compile vs committed inklecate `.ink.json`, hermetic, on `clean` (primary); JS-bridge cross-check on `with-oracle-macos` (secondary) | 100% line/choice identical | any divergence fails CI (North-Star gate; blocks merge) |
| **#2** Unsupported-construct rejection | clear located error, not a broken story | unsupported-construct corpus test (named + located error, no story) | 100% rejected | **HARD GUARDRAIL: 0% silent wrong output — must never regress** |
| **#3** Doc-vs-compiler consistency | author predicts compile/reject from the reference | doc-vs-compiler consistency test over the reference construct list | 100% documented; statuses match compiler | a doc/compiler disagreement fails CI |
| **#4** No-inklecate guardrail | supported builds compile without inklecate | source guard (no `Process`/inklecate in production `Compiler/`) + no-subprocess test | 0 inklecate invocations | any `Process`/inklecate reference or spawned subprocess fails CI |

---

## Wave: DEVOPS / [REF] Deployment Strategy

**N/A — SPM library version bump.** A library has no running instances to roll out, no
traffic to shift, and no canary/blue-green/rolling strategy. A "release" is a **git tag
+ semantic version bump** (and raising `swift-tools-version` to 5.8 when `Compiler/`
lands). **Rollback** is reverting the tag. Pre-release readiness = the commit-stage CI
gates above are green. No deployment scripts, environment promotion, or runtime smoke
tests apply.

---

## Wave: DEVOPS / [REF] Mutation Testing Strategy

**DISABLED** — a durable project constraint, not a deferral. Maintainer rationale: no
reliable/proven Swift mutation-testing solution exists; Muter was flaky at best after
significant effort. Test quality is instead validated by the **execution-equivalence
oracle suite** (every supported slice is checked line/choice-for-choice against
inklecate via the InkSwift oracle), **code review**, and the **CI boundary gates**
(R1/R3/R5). Persisted with maintainer approval to `CLAUDE.md` `## Mutation Testing
Strategy`.

---

## Wave: DEVOPS / [REF] Observability Stack

**CI test-gate metrics only; no runtime telemetry.** A compiler library emits no
runtime signals (no requests, latency, error rates, saturation) to observe — RED/USE/
Golden-Signals and SLO/error-budget machinery are **N/A** for a library. The "metrics"
that matter are the four KPI CI gates (above), measured per CI run. Instrumenting
runtime telemetry here would invent infrastructure that does not apply. (Density
telemetry JSONL infra does not exist in this Swift repo and is intentionally skipped.)

---

## Wave: DEVOPS / [REF] Branching Strategy

**Trunk-Based Development.** Single `main`; short-lived slice branches (S0..S6, ≤ ~1
day); CI gates on every `push` + `pull_request`. `main` is always releasable; releases
are tags off `main`. This aligns with the existing `tests.yml` triggers (no branch
filter — all pushes/PRs run) and the slice-per-deliverable cadence. No long-lived
develop/release branches; no GitFlow.

---

## Wave: DEVOPS / [REF] Coexistence Matrix

| Concern | Requirement | Impact of feature |
|---|---|---|
| Forgejo CI (`tests.yml`) | keep working (swift test, macos-arm64, push + PR) | additive only; lint + guardrail gates wired alongside first `Compiler/` slice |
| Frozen InkSwift (JS-bridge) + JXKit | untouched (D8); remains the macOS oracle | none — compiler imports nothing from InkSwift; JXKit unchanged |
| Existing 154-test runtime suite | stay green | none — new files under `Compiler/` + additive `Facade/` inits only |
| Public API (`StoryBlueprint(json:)`) | unchanged (D8, DDD-2) | only internal `StoryBlueprint(root:)` + new compile entry added |

---

## Wave: DEVOPS / [REF] Pre-requisites (DESIGN constraints the platform satisfies)

- **R5/R1/R3 enforcement** — `.swiftlint.yml` authored with path-scoped `custom_rules`; verified `0 violations` on the current tree; activates as `Compiler/` lands.
- **Oracle availability** — `with-oracle-macos` provides the InkSwift JS-bridge; committed `.ink.json` fixtures (offline inklecate provenance, REGEN-gated).
- **Swift version** — `swift-tools-version` 5.6 → 5.8 raised when the `Compiler/` target lands (DDD-11); deferred so the current build is undisturbed.
- **Compiler accepted set == runtime supported set** (D1); no-inklecate guardrail (KPI #4); 0% silent wrong output (KPI #2) — all enforced as CI gates.

---

## Wave: DEVOPS / [REF] Back-Propagation to DESIGN

**None.** Every DEVOPS decision (D1-D9 in `devops/wave-decisions.md`) aligns with DESIGN
(DDD-1..DDD-12) and DISCUSS (D1-D8). No DESIGN assumption is contradicted, so no
`## Changed Assumptions` block and no `devops/upstream-changes.md` are required.

---

# Feature Delta: native-ink-compiler (DISTILL wave)

**Wave**: DISTILL | **Acceptance Designer**: Sentinel-authored, orchestrator-run
**Date**: 2026-06-14 | **Density**: lean (Tier-1 [REF])
**Status**: acceptance suite written + RED-classified; pending Final Wave Review Gate.

> Acceptance tests are **Swift Testing** `@Test func` oracle suites with backtick
> names (project convention + `CLAUDE.md` mandate), NOT Gherkin/pytest-bdd. The
> skill's Python examples are adapted to the existing Milestone oracle harness.
> The executable `.swift` suites under `Tests/SwiftInkRuntimeTests/Acceptance/`
> are the scenario SSOT; the sections below are pointers + structured summaries.

---

## Wave: DISTILL / [REF] Reconciliation Gate

**Reconciliation passed — 0 contradictions.** All three prior-wave `wave-decisions.md`
(DISCUSS D1-D8, DESIGN DDD-1..DDD-12 / Forks 1-4, DEVOPS D1-D9) are mutually
consistent; ADR-006/007/008/009 are all **Accepted (user-confirmed 2026-06-14)**.
No DISCUSS decision is contradicted by DESIGN or DEVOPS. Scenario writing proceeded.

Graceful-degradation matrix: DISCUSS/DESIGN/DEVOPS artifacts all present — no WARN/BLOCK.

---

## Wave: DISTILL / [REF] Scenario List (tags)

Executable SSOT: `Tests/SwiftInkRuntimeTests/Acceptance/Compiler_*.swift`.
Each non-skeleton suite maps to one DELIVER slice (one-at-a-time: a slice's suite
flips GREEN as its codegen lands). 37 tests total; 36 RED + 1 GREEN guardrail.

| Suite / Scenario | Slice / Story | Tags |
|---|---|---|
| `Compiler_S0` one line compiles in-process, matches oracle | S0 / US-01 | `@walking_skeleton @driving_adapter @real-io @us-01 @kpi-1` |
| `Compiler_S0` convenience surface yields a playable story | S0 / US-01 | `@driving_adapter @us-01` |
| `Compiler_S0` empty source ends cleanly | S0 / US-01 | `@us-01 @boundary` |
| `Compiler_S0` secondary JSON sink emits Ink-JSON | S0 / US-01 (D4) | `@driving_adapter @us-01` |
| `Compiler_S1` multi-knot linear story matches oracle | S1 / US-02 | `@us-02 @real-io @kpi-1` |
| `Compiler_S1` glue joins lines as oracle | S1 / US-02 | `@us-02 @real-io` |
| `Compiler_S2` state-driven story matches oracle | S2 / US-03 | `@us-03 @real-io @kpi-1` |
| `Compiler_S2` CONST inlining + arithmetic match oracle | S2 / US-03 (D6) | `@us-03 @real-io` |
| `Compiler_S3` weave corpus choice-for-choice identical ×4 | S3 / US-04 | `@us-04 @real-io @kpi-1 @weave-spike` |
| `Compiler_S4` full ceiling matches oracle | S4 / US-05 | `@us-05 @real-io @kpi-1` |
| `Compiler_S4` functions/tunnels/ref-param match oracle | S4 / US-05 | `@us-05 @real-io` |
| `Compiler_S4` The Intercept native compile == oracle (e2e) | S4 / US-05 | `@us-05 @real-io @kpi-1` |
| `Compiler_S5` documented-supported actually compiles ×5 | S5 / US-07 | `@us-07 @kpi-3` |
| `Compiler_S5` documented-unsupported actually rejected ×8 | S5 / US-07 | `@us-07 @kpi-3 @error` |
| `Compiler_S6` unsupported construct rejected, named+located ×8 | S6 / US-06 | `@us-06 @error @kpi-2` |
| `Compiler_NoInklecate` production refs no inklecate/Process | KPI #4 | `@us-04 @kpi-4 @guardrail` (GREEN) |

Error/edge coverage: S5(8) + S6(8) reject scenarios + S0 boundary = **≥45%** of
scenarios are error/edge — exceeds the 40% target. Sad paths are enumerated, one
construct per fixture (Mandate 11 — never PBT-generated).

---

## Wave: DISTILL / [REF] Walking-Skeleton Strategy

Per the project **ATDD Infrastructure Policy** (`docs/architecture/atdd-infrastructure-policy.md`,
bootstrapped this wave — first DISTILL in the repo). Port-class → treatment:
driving = real in-process call; driven-internal (`ContainerNode` runnable tree) =
real; driven-external (inklecate) = test-only committed `.ink.json` fixture.

WS scenario: `Compiler_S0` — one line of plain text compiled in-process through the
production `InkCompiler.compile` entry point, played through the real `Story`
runtime, output matched line-for-line to the inklecate oracle (`@walking_skeleton
@driving_adapter`). Litmus: a stakeholder confirms "compile a story in pure Swift,
no external binary, get the same output" — yes. **Authored RED** (DWD-2): no SPIKE
promoted a skeleton, so S0 goes GREEN in DELIVER S0 (it is the first slice).

---

## Wave: DISTILL / [REF] Adapter Coverage (Mandate 6)

| Driven adapter | `@real-io` scenario | Covered by |
|---|---|---|
| inklecate oracle (test-only) | YES | committed `.ink.json` fixtures (offline provenance) replayed in every S0-S4 equivalence test |
| Source/INCLUDE filesystem read | YES | every compile test reads the real `.ink` SOURCE from `Bundle.module` (`CompilerOracle.source`) |
| Runnable-story tree (`ContainerNode`) | YES | every compile+play test constructs `Story(blueprint:)` and plays the real tree |
| InkSwift JS-bridge (macOS, secondary) | inherited | existing Milestone oracle harness (`#if os(macOS)`); the compiler reuses it as Level-2 ground truth |

Zero "NO — MISSING" rows. inklecate is the only external; it is a test-only fixture
source (not a per-CI dependency), satisfying the costly-external allowance.

---

## Wave: DISTILL / [REF] Scaffolds (Mandate 7)

RED-ready Swift stubs (`// SCAFFOLD: true`; throw `CompileError(kind: .scaffold)`
so failures classify RED, never BROKEN). Detect: `grep -rn "SCAFFOLD: true" Sources/`.

- `Sources/SwiftInkRuntime/Compiler/InkCompiler.swift` — `compile(source:)`,
  `compile(fileURL:)`, `emitJSON(source:)`, `Story(inkSource:)` convenience.
- `Sources/SwiftInkRuntime/Compiler/Error/CompileError.swift` — `CompileError`
  (`kind`, `construct`, `message`, `line`, `column`) + `CompileErrorKind`
  (`unsupportedConstruct` / `syntaxError` / `unresolvedReference` / `scaffold`).

DELIVER removes the `.scaffold` sentinel + markers slice-by-slice; zero markers
remain at feature completion.

---

## Wave: DISTILL / [REF] Test Placement

- Suites: `Tests/SwiftInkRuntimeTests/Acceptance/Compiler_*.swift` + shared
  `CompilerOracleSupport.swift` — mirrors the existing `Milestone*`/`WalkingSkeleton`
  acceptance precedent (same dir, same `@testable import` + `#if os(macOS) import
  InkSwift` harness).
- Fixtures: `Tests/SwiftInkRuntimeTests/*.ink` (source) + `*.ink.json` (oracle),
  registered as `.process` resources in `Package.swift` (alongside existing slice
  fixtures). `TheIntercept.ink` source copied in for the e2e ceiling test.

---

## Wave: DISTILL / [REF] Driving-Adapter Coverage

| DESIGN entry point | Protocol | AT exercising it |
|---|---|---|
| `InkCompiler.compile(source:)` (primary, DDD-10) | in-process call | S0 WS `@driving_adapter` + every S1-S6 suite |
| `Story(inkSource:)` convenience (DWD-1) | in-process call | S0 convenience-surface test |
| `InkCompiler.emitJSON(source:)` (secondary D4) | in-process call | S0 JSON-sink test |

No CLI/HTTP/hook adapter in this feature (library API only); subprocess/HTTP
protocol coverage is N/A. The no-inklecate guardrail asserts the compile path
spawns no subprocess (KPI #4).

---

## Wave: DISTILL / [REF] Pre-requisites

- DESIGN driving ports: `InkCompiler.compile` / `emitJSON` / `Story(inkSource:)` — scaffolded.
- DEVOPS environment matrix: `clean` (PRIMARY — build + hermetic KPI #1 + reject +
  doc-consistency + guardrail; cross-platform) and `with-oracle-macos` (SECONDARY
  JS-bridge cross-check). UI-1 **applied** (maintainer-confirmed 2026-06-14): the
  core equivalence comparison imports no `InkSwift`, so KPI #1 now runs hermetically
  on `clean`; `kpi-contracts.yaml`, `environments.yaml`, and the DEVOPS sections were
  updated to match. See `distill/upstream-issues.md`.
- inklecate (`/Users/Maarten.Engels/.local/bin/inklecate`) — verified working;
  generated all 8 supported `.ink.json` oracle fixtures offline (REGEN provenance).

---

## Wave: DISTILL / [REF] Outcomes Registry

**N/A — correctly skipped.** The `nwave-ai outcomes register` CLI and
`docs/product/outcomes/registry.yaml` do not exist in this Swift repo (registry is
Python-tool infrastructure). The feature's typed contracts (`InkCompiler.compile`,
`CompileError`, the reject specification) are tracked instead by `kpi-contracts.yaml`
(KPI #1-#4) and the executable acceptance SSOT. Recorded here so the skip is explicit,
not silent.

---

## Wave: DISTILL / [REF] DISTILL Wave Decisions (DWD)

| # | Decision | Rationale |
|---|---|---|
| DWD-1 | Public compile surface = `InkCompiler.compile(source:)` primary (DDD-10) + `Story(inkSource:)` convenience; both exercised. | Resolves DESIGN deferred Q#4 ("and/or"); DDD-10 names compile as THE driving port, convenience aids ergonomics. |
| DWD-2 | Walking skeleton authored **RED**; goes GREEN in DELIVER S0. | No SPIKE promoted a skeleton, so the "WS green at handoff" rule cannot apply; S0 is the first slice to GREEN. Justified deviation. |
| DWD-3 | ATs are Swift Testing oracle suites, not Gherkin/pytest-bdd. | Project conventions win (skill LANGUAGE CONVENTION FRAME); `CLAUDE.md` backtick mandate; reuse Milestone harness. |
| DWD-4 | Execution-equivalence = native compile vs committed inklecate `.ink.json`, both via the production runtime along the same choice script. The compiler ATs import no `InkSwift` (verified). | Level-1 oracle (D5). Because the comparison needs no JS-bridge it is *also* hermetic/cross-platform. Surfaced as back-propagation UI-1 and **applied (maintainer-confirmed 2026-06-14)**: `kpi-contracts.yaml` / `environments.yaml` / the DEVOPS sections now run KPI #1 hermetically on `clean`; the macOS JS-bridge remains the secondary ground truth. See `distill/upstream-issues.md` UI-1. |
| DWD-5 | Reject corpus is example-only/enumerated, one construct per fixture. | Mandate 11 — sad paths never PBT-generated; KPI #2 needs per-construct named+located assertions. |
| DWD-6 | The S3 four-fixture weave corpus (flat/nested/labeled-gather/sealed) **is** the ADR-008 spike gate. | DDD-6: S3 sizing committed in DELIVER only after these pass oracle line/choice identity. |
| DWD-7 | Outcomes registry skipped (N/A — no `nwave-ai` CLI in this repo). | Recorded explicitly; KPI contracts + executable SSOT track the typed contracts. |
| DWD-8 | Mandate-8/12 (`assert_state_delta`/Universe, step-reuse ratio) N/A. | Those are pytest-bdd/Python infra; the project's correctness instrument is the oracle suite. Project conventions win. |
| DWD-9 | Tier B (state-machine PBT) **skipped**; Tier A oracle equivalence only. | Observable is line/choice equivalence modeled by example fixtures; no domain-rich input space warranting `RuleBasedStateMachine` (Two-Tier guidance). |

---

## Wave: DISTILL / [REF] Self-Review Checklist

- [x] WS strategy declared (Infrastructure Policy + WS section).
- [x] WS/equivalence scenarios tagged (`@real-io`, `@walking_skeleton`).
- [x] Every driven adapter has a `@real-io` scenario (coverage table, 0 missing).
- [x] In-memory doubles: none used (real runtime + real fixtures); N/A documented.
- [x] inklecate test-only/offline preference documented (Infra Policy + DWD-4).
- [x] Mandate 7: all imported production modules scaffolded (`InkCompiler`, `CompileError`).
- [x] Driving adapters (compile / convenience / emitJSON) each exercised by ≥1 scenario.
- [x] Mandate 7: scaffolds carry `// SCAFFOLD: true`.
- [x] Mandate 7: scaffold methods throw `CompileError` (assertion-class RED), not a fatal/infra error.
- [x] Mandate 7: tests run RED (not BROKEN) — verified via `swift test` + `distill/red-classification.md`.
- [x] ≥1 `@real-io` scenario per driven adapter (synthetic-data gap closed by real bundled `.ink`).
- [x] Timing assertions: none (no flaky budgets introduced).
- [x] Boundary R5 respected — `Story(inkSource:)` lives in the `Compiler/` layer, `Facade/` does not import `Compiler/`.
- [x] Existing 154-runtime suite stays GREEN (now 232 tests; 0 regressions).

---

## Wave: DISTILL / [REF] Pre-DELIVER Gate Result

`swift test` → **fail-for-the-right-reason PASS**. 36/36 failing compiler scenarios
classify `MISSING_FUNCTIONALITY` (scaffold), 0 BROKEN, 0 wrong-assertion; 1 guardrail
GREEN; all prior suites GREEN (233 tests total). Full classification:
`docs/feature/native-ink-compiler/distill/red-classification.md`. **DELIVER handoff
unblocked** pending the Final Wave Review Gate below.

---

# Feature Delta: native-ink-compiler (DELIVER wave)

**Wave**: DELIVER | **Orchestrator**: Main instance (nw-deliver) | **Date**: 2026-06-14
**Density**: lean (Tier-1 [REF]) | **Scope**: slices S0, S1, S2 (of S0–S6) | **Crafter**: @nw-software-crafter (object-oriented, example-based)
**Branch**: `feat/native-ink-compiler-deliver`

> **Scope note**: This DELIVER pass shipped slices **S0 (walking skeleton), S1 (core flow), S2 (variables & expressions)** only. Slices S3 (choices/gathers — weave-spike gated), S4 (ceiling), S5 (reference consistency), S6 (unsupported rejection) remain authored-RED in the DISTILL suite and are **future slices**, intentionally out of this scope.

## Wave: DELIVER / [REF] Implementation Summary

Built the native, in-process Ink compiler spine — `read → CommentEliminator → StringParser → InkParser (AST) → RuntimeObjectEmitter → StoryBlueprint(root:) → runnable Story` — with **no JSON round-trip** (D3) and **no external inklecate** (KPI #4). S0 compiles plain text and the empty story; S1 adds knots, stitches, absolute/qualified/relative (`.^`) diverts, and glue, lowering them to `namedContent` and resolved `.divert` nodes; S2 adds a Pratt expression sub-parser, arithmetic (postfix/RPN emission matching the runtime eval stack), VAR/CONST/temp declarations with **compile-time CONST inlining** (D6/DDD-9), variable reads, and string interpolation. A secondary `emitJSON` Ink-JSON sink (D4) is delivered using `JSONEncoder`/string building (never `JSONSerialization`, R3). All comparison is **execution-equivalence** (native compile vs committed inklecate `.ink.json`, both played through the same runtime) — not structural-JSON parity.

## Wave: DELIVER / [REF] Files Modified

**Production (Compiler/ layer + one Facade extend):**
- `Compiler/Lexer/CommentEliminator.swift` — strip `//` and `/* */`, string-literal + escaped-quote aware.
- `Compiler/Parser/StringParser.swift` — stateful cursor with line/column tracking + combinators.
- `Compiler/Parser/InkParser.swift` — statement rules → AST (knot/stitch/divert/glue/END/text).
- `Compiler/Parser/InkParserExpressions.swift` — Pratt precedence-climbing expression sub-parser (escaped-quote aware string scan).
- `Compiler/AST/CompilerAST.swift` — typed parsed-AST nodes with source positions + unresolved divert paths.
- `Compiler/Codegen/RuntimeObjectEmitter.swift` — AST → `ContainerNode`/`NodeKind`; divert resolution, glue, postfix arithmetic, CONST inlining, global-decl container, interpolation.
- `Compiler/Codegen/JSONEmitter.swift` — secondary Ink-JSON sink (D4), no `JSONSerialization`.
- `Compiler/Error/CompileError.swift` — located, construct-named error (ADR-009); `.scaffold` case retained for S3–S6.
- `Compiler/InkCompiler.swift` — driving port `compile(source:)`/`emitJSON`; `Story(inkSource:)` convenience.
- `Facade/StoryBlueprint.swift` — EXTEND: internal `init(root: ContainerNode)` no-JSON seam (DDD-2).

**Tests (DELIVER unit, example-based, backtick names):**
- `Tests/.../Unit/CommentEliminatorTests.swift`, `StringParserTests.swift`, `InkParserTests.swift`, `InkExpressionTests.swift`.
- DISTILL-authored acceptance suites `Compiler_S0/S1/S2*.swift` flipped GREEN (not modified).

## Wave: DELIVER / [REF] Scenarios Green Count

**8 of 8 in-scope acceptance scenarios GREEN** (2026-06-14): S0 4/4 (plain-text compile+play, convenience surface, empty source, emitJSON sink), S1 2/2 (multi-knot linear, glue), S2 2/2 (state-driven, CONST inlining+arithmetic). Plus 25 DELIVER unit tests + KPI #4 no-inklecate guardrail GREEN. Out-of-scope S3–S6 acceptance scenarios remain RED by design (future slices). Full suite: 262 tests; 0 pre-existing regressions.

## Wave: DELIVER / [REF] DoD Check (in-scope)

- [x] KPI #1 (oracle execution-equivalence) — S0/S1/S2 supported corpus plays line-for-line identical to inklecate oracle.
- [x] KPI #4 (no-inklecate guardrail) — production `Compiler/` references no `Process`/inklecate; no subprocess spawned (test-verified).
- [x] D3 (no JSON round-trip) — primary path uses `StoryBlueprint(root:)`; D4 emitJSON is a separate secondary sink.
- [x] D6/DDD-9 (CONST inlining) — `BONUS` inlined to literal; no runtime CONST variable (oracle-verified: Total: 13).
- [x] R3/R5 boundary gates — SwiftLint `--strict` 0 violations (no Engine import, no JSONSerialization in Compiler/).
- [~] KPI #2 (unsupported rejection) / KPI #3 (doc consistency) — out of scope (S5/S6 future slices).

## Wave: DELIVER / [REF] Demo Evidence

This is a library API (no CLI/HTTP adapter — DISTILL Driving-Adapter Coverage); the dogfood moment ("compile a story in pure Swift, no external binary, get the same output as inklecate") is realised by the `@real-io` execution-equivalence acceptance tests. Captured 2026-06-14 via `swift test`:

```
Suite "Compiler S0 — Walking Skeleton (compile and play one line)"  passed
Suite "Compiler S1 — Core Flow (knots, stitches, diverts, glue)"     passed
Suite "Compiler S2 — Variables & Expressions (VAR, CONST, temp, ...)" passed
Suite "Compiler — No-inklecate Guardrail (KPI #4)"                    passed
Test run with 22 tests in 7 suites passed
```
S2 renders `Hello, Ada.` / `Score: 3` / `Total: 13` / `Math: 14` — identical to the inklecate oracle.

## Wave: DELIVER / [REF] Quality Gates

| Phase | Outcome |
|---|---|
| Roadmap review (nw-acceptance-designer-reviewer) | REJECTED once (02-01 enabling-step framing) → fixed → APPROVED |
| Per-step TDD (3-phase canon RED→GREEN→COMMIT) | 6/6 steps COMMIT/PASS; DES integrity: all 6 steps complete traces (exit 0) |
| Post-merge integration gate (3.5) | PASS — 9 in-scope acceptance + guardrail GREEN, 0 regressions |
| L1–L6 refactoring (Phase 3) | Applied (L1 dead-code/readability; stale scaffold headers removed; `.scaffold` case retained) |
| Adversarial review + Testing Theater (Phase 4) | REJECTED once (escaped-quote BLOCKER) → fixed via TDD → resolved |
| Mutation testing (Phase 5) | SKIPPED — disabled project-wide (CLAUDE.md / DEVOPS) |
| Deliver integrity verification (Phase 6) | PASS (exit 0) |
| SwiftLint R1/R3/R5 boundary gate | 0 violations across all passes |

## Wave: DELIVER / [REF] Pre-requisites (consumed)

DISTILL acceptance suites (`Compiler_S0/S1/S2`) + `CompilerOracleSupport.swift` + committed inklecate `.ink.json` oracle fixtures; DESIGN Component Decomposition (Lexer/Parser/AST/Codegen/Error/InkCompiler), DDD-2 (`StoryBlueprint(root:)`), DDD-5 (hand-rolled Pratt parser), DDD-9/D6 (CONST inlining); DEVOPS R5/R3 SwiftLint `custom_rules` (already live).

---

# Feature Delta: native-ink-compiler (DELIVER wave — S3–S6 continuation, 2026-06-14)

**Wave**: DELIVER (continuation pass) | **Orchestrator**: Main instance (nw-deliver) | **Date**: 2026-06-14
**Density**: lean (Tier-1 [REF]) | **Scope**: slices S3, S4, S5, S6 (completing S0–S6) | **Crafter**: @nw-software-crafter (object-oriented, example-based)
**Branch**: `feat/native-ink-compiler-deliver` | **Commits**: `2e714a2..HEAD`

> **Scope note**: This continuation pass shipped the remaining slices — **S3 (choices/gathers/weave), S4 (ceiling: conditionals/functions/tunnels/ref-params/tags), S5 (feature-reference consistency), S6 (unsupported-construct rejection)** — on top of the S0–S2 spine above. With this pass the native compiler covers the full supported ceiling (matrix rows 1–35) and rejects the unsupported set (rows 25–28, 36–39). Two roadmap adjustments were made during the pass and recorded in `roadmap.json` scope_note — see [WHY] Upstream Issues below.

## Wave: DELIVER / [REF] Implementation Summary

Completed the native compiler to the full supported ceiling. **S6** (steps 06-01/06-02) landed first as a guardrail: a `UnsupportedConstructDetector` that rejects variable-text sequences/cycles/once/shuffle and thread/LIST/RANDOM/EXTERNAL with a located `.unsupportedConstruct` error before any codegen, so no unsupported input can slip through silently during S3/S4 development. **S3** (step 03-01) delivered the general **weave resolver** — the research-flagged highest-risk algorithm — handling nested weaves, labeled and multiple gathers, sticky/plain/labeled choices, and sealed weaves; the choice-flag/invisible-default encoding (originally roadmap step D6) was validated by the S3 oracle corpus and **folded** into the resolver step. **S4** (steps 04-01/04-02) added conditionals (inline/block/switch — new `ConditionalEmitter`) + tags lowering, then functions + inline calls, tunnels, and reference parameters. **S5** (step 05-01) authored `docs/product/ink-feature-reference.md` (US-07), the supported/unsupported reference whose statuses match actual compiler behaviour. An L1–L6 refactor then cleaned the S3–S6 compiler code. All correctness is judged by **execution-equivalence** against the committed inklecate oracle.

## Wave: DELIVER / [REF] Files Modified

**Production (Compiler/ layer):**
- `Compiler/Codegen/WeaveEmitter.swift` — general weave resolver (nested weaves, labeled/multiple gathers, sticky/plain/labeled choices, sealed weaves); emits the choice-flag bitfield + invisible-default encoding (folded D6).
- `Compiler/Codegen/ConditionalEmitter.swift` — **new**: inline / block (if / else if) / switch-style conditional lowering; fixed a `true`/`false` bool-literal emission bug.
- `Compiler/Codegen/RuntimeObjectEmitter.swift` — EXTEND: functions + inline calls, tunnels (`-> k ->`), reference parameters, tags wiring.
- `Compiler/Parser/InkParser.swift` — EXTEND: choices/gathers/weave structure, conditionals, function/knot definitions; fixed a two-equals-vs-three-equals knot-marker bug.
- `Compiler/Parser/InkParserExpressions.swift` — EXTEND: inline conditional / function-call / tunnel expression forms.
- `Compiler/Parser/UnsupportedConstructDetector.swift` — **new**: locates and rejects rows 25–28, 36–39 with `.unsupportedConstruct(construct, location)`.
- `Compiler/AST/CompilerAST.swift` — EXTEND: weave/choice/gather/conditional/function/tunnel/ref-param/tag AST nodes with source positions.

**Tests:**
- DISTILL-authored acceptance suites `Compiler_S3_ChoicesGathersTests`, `Compiler_S4_CeilingTests`, `Compiler_S5_FeatureReferenceConsistencyTests`, `Compiler_S6_UnsupportedRejectionTests` activated (flipped GREEN, not modified). The TheIntercept S4 end-to-end test is committed `.disabled` (descoped — see [WHY] below).
- 2 new DELIVER unit suites (weave-resolver + unsupported-detector example coverage, backtick names).

**Docs:**
- `docs/product/ink-feature-reference.md` — **new** (US-07): every construct as MUST-COMPILE / MUST-REJECT with example + reason, derived from the Feature Coverage Matrix.

## Wave: DELIVER / [REF] Scenarios Green Count

(2026-06-14) **S3 4/4** weave fixtures (flat / nested / labeled-gather / sealed) GREEN — these *are* the ADR-008 weave-spike gate. **S4 2/2** active scenarios GREEN (+1 TheIntercept e2e intentionally `.disabled` / descoped). **S5 13/13** doc-vs-compiler consistency cases GREEN. **S6 8/8** unsupported-construct rejections GREEN (each located + construct-named). **Full suite: 280 tests GREEN**, 0 pre-existing regressions (TheIntercept S4 test `.disabled`).

## Wave: DELIVER / [REF] DoD Check (S3–S6)

- [x] KPI #1 (oracle execution-equivalence) — weave (S3) and full-ceiling (S4) supported corpus plays line-for-line + choice-for-choice identical to the inklecate oracle.
- [x] KPI #2 (unsupported rejection / 0% silent wrong output) — 8/8 unsupported constructs rejected with named + located `.unsupportedConstruct`; none produce a story.
- [x] KPI #3 (doc-vs-compiler consistency) — `ink-feature-reference.md` statuses match actual compiler behaviour (S5 13/13 GREEN).
- [x] KPI #4 (no-inklecate guardrail) — still GREEN; production `Compiler/` spawns no subprocess.
- [x] R3/R5 SwiftLint boundary gates — `--strict` 0 violations across S3–S6.

## Wave: DELIVER / [REF] Demo Evidence

This is a library API (no CLI/HTTP adapter — DISTILL Driving-Adapter Coverage); the dogfood moment is realised by the `@real-io` execution-equivalence acceptance suites. With this pass S3/S4/S5/S6 are GREEN and the **full 280-test suite passes** (`swift test`), proving a branching, full-ceiling supported story compiles in pure Swift and plays oracle-identical, while every unsupported construct is rejected with a clear located error.

## Wave: DELIVER / [REF] Quality Gates

| Phase | Outcome |
|---|---|
| Roadmap review (nw-acceptance-designer-reviewer) | APPROVED |
| Per-step TDD (3-phase canon RED→GREEN→COMMIT) | 6/6 new steps (06-01, 06-02, 03-01, 04-01, 04-02, 05-01) COMMIT/PASS complete traces |
| Post-merge integration gate | PASS — 280 tests GREEN, 0 regressions |
| L1–L6 refactoring (Phase 3) | Applied to S3–S6 compiler code (`2f0454a`) |
| Adversarial review + Testing Theater (Phase 4) | APPROVED — 0 blockers, 0 testing-theater |
| Mutation testing (Phase 5) | SKIPPED — disabled project-wide (CLAUDE.md) |
| Deliver integrity verification (Phase 6) | PASS (exit 0) — all 12 steps complete RED/GREEN/COMMIT traces |
| SwiftLint R1/R3/R5 boundary gate | 0 violations |

## Wave: DELIVER / [WHY] Upstream Issues

- **The Intercept uses a sequence — the DESIGN brief is wrong.** The brief's "Ink Feature Coverage" claims The Intercept exercises Parts 1–4 "without using sequences." This is **inaccurate**: `TheIntercept.ink` line 86 contains a variable-text sequence `{|I rattle my fingers on the field table.|}`. Because the native compiler **correctly rejects** sequences (matrix rows 25–28; S6 / DDD-12 / DDD-8), The Intercept cannot be natively compiled today.
- **Consequence — e2e descoped.** The TheIntercept native-compile end-to-end step was **descoped** (user-approved 2026-06-14); its S4 acceptance test is committed `.disabled`. The remaining S4 corpus exercises the full supported ceiling without it.
- **Parity-gap finding (future-work candidate).** The *runtime* can already play `{|...|}`: inklecate lowers it to a visit-count switch (visit + MIN + `==` + conditional diverts), all of which the runtime executes — which is why the Milestone5b playthrough renders the first 100 lines (line 86 shows empty on first visit). So deterministic variable-text (sequence/cycle/once) is a documented **compiler/runtime parity gap** the compiler could close in future; shuffle additionally needs RANDOM (genuinely runtime-unsupported). **User decision (2026-06-14): keep sequences rejected as specced, descope the e2e, do not expand the supported set this pass.**
- **Roadmap fold (D6 → S3).** The standalone choice-flag / invisible-default encoding step (D6) was **folded** into the weave-resolver step: the S3 oracle corpus validates the encoding per DDD-9 and was 4/4 GREEN once the resolver landed, so a separate step was redundant.
