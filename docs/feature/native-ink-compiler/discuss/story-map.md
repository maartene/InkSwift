# Story Map: native-ink-compiler

## User: Maarten — Swift app developer embedding Ink stories
## Goal: Compile a .ink story to a runnable story entirely in Swift, with no external inklecate binary, failing loud on unsupported features.

The backbone mirrors how a developer actually moves through compilation, and the
ribs mirror how the *runtime* itself was built tier by tier (so the compiler's
scope tracks the runtime's scope exactly). Two activities — "Stay in bounds" and
"Fail loud" — are first-class, not afterthoughts, because the user explicitly
asked for a clear supported/unsupported description and non-silent failures.

## Backbone

| A. Get source in | B. Compile core flow | C. Compile logic & choices | D. Run & verify | E. Stay in bounds | F. Fail loud on unsupported |
|---|---|---|---|---|---|
| Read a .ink source | Compile plain text end-to-end (skeleton) | Compile variables & expressions | Play compiled story in runtime | Read supported/unsupported reference | Reject unsupported construct with located error |
| | Compile knots/stitches/diverts/glue | Compile choices, gathers, read counts | Compare to inklecate oracle | | Point to the feature reference from the error |
| | | Compile conditionals/functions/tunnels/ref-params/tags | | | |

---

### Walking Skeleton (S0)

The thinnest end-to-end task drawn from each backbone activity that the skeleton
needs to touch:
- **A**: read a one-line `.ink` source (`Hello, world.`)
- **B**: parse + codegen that single line
- **D**: play the compiled story in the runtime; emitted text == `Hello, world.`;
  matches the inklecate oracle

The skeleton deliberately does NOT touch C, E, or F — it proves the *spine*
(read -> parse -> codegen -> runnable story -> execute -> oracle match) on the
smallest possible input, nothing more.

### Release 1: "Compile a real linear story" (outcome: a no-choice story plays natively, oracle-matched)
- **S1** Tier-1 core flow: knots, stitches, all divert forms (absolute/relative/anchor), glue, text/newlines.
- **S2** Variables & expressions: VAR globals, CONST (with compile-time inlining — runtime does not do this), temp vars, assignment, variable read in output, arithmetic/logic operators, string interpolation.
- Outcome KPI targeted: a linear (choice-free) supported story compiles in-process and plays line-for-line identically to the inklecate oracle.

### Release 2: "Compile an interactive story" (outcome: choice-driven stories play natively, oracle-matched)
- **S3** Choices, gathers, read counts: plain/bracketed/sticky/conditional choices; gathers + labeled gathers; knot visit counters; plus the compile-time choice-flag + invisible-default encoding (matrix row 10) the runtime assumes was done.
- Outcome KPI targeted: a story with choices and gathers compiles and plays identically to the oracle along fixed choice paths.

### Release 3: "Compile The Intercept ceiling" (outcome: the full supported feature set compiles, oracle-matched)
- **S4** Conditionals, functions, tunnels, ref params, tags: inline `{c:a|b}`, block if/else-if, switch-style; functions `=== f() ===` + inline calls `{f()}`; tunnels `-> k ->`; reference parameters `ref x`; tags `#tag`.
- Outcome KPI targeted: a story exercising the complete supported set (up to The Intercept ceiling) compiles and plays identically to the oracle.

### Release 4: "No surprises" (outcome: authors know bounds and never ship silent breakage)
- **S5** Supported/unsupported feature reference document (first-class deliverable; a readable matrix the author consults).
- **S6** Unsupported-feature error reporting: every unsupported construct (variable-text sequences/cycles/once/shuffle, threads, LIST, RANDOM/SEED_RANDOM, external functions) is rejected with a clear error naming the construct and its source location — never silent wrong output.
- Outcome KPI targeted: zero silent wrong output on unsupported input; authors can predict compile/reject from the reference.

> S5 and S6 are sequenced last in this map for *narrative* clarity, but see the
> Priority Rationale — S6 (fail-loud) is risk-derisking and is recommended to
> ship alongside the earliest slices so unsupported input never silently
> mis-compiles during S1-S4 development. S5's MUST-REJECT half depends on S6's
> detection list.

---

## Priority Rationale

Priority order is driven by outcome impact and dependency, with the walking
skeleton and riskiest-assumption-first rules from the methodology.

1. **S0 Walking skeleton — P1.** Validates the riskiest *structural* assumption:
   that the entire pipeline can be wired in pure Swift and produce a runtime-
   consumable story matching the oracle. Everything else is incremental once the
   spine exists. (Tie-break: Walking Skeleton > all.)

2. **S6 fail-loud detection (at least the detection skeleton) — P2, ship early.**
   Riskiest *product* assumption after the spine: the user's hardest constraint is
   "never fail silently." If unsupported constructs can slip through during S1-S4,
   we risk building on silently-wrong foundations. Standing up construct
   *detection + error* early (even before every supported feature is done) means
   every later slice is developed against a compiler that refuses what it cannot
   yet (or will never) handle. Recommended to land its detection mechanism
   alongside S1.

3. **S1 core flow then S2 variables — P3.** Highest-value supported behaviour:
   a real linear story playing natively. Ordered S1 before S2 because expressions
   and variable-read-in-output (S2) build on text/divert flow (S1). CONST inlining
   in S2 is a named compile-time obligation the runtime depends on.

4. **S3 choices & gathers — P4.** Unlocks interactive stories — the majority of
   real Ink content. Depends on S1/S2 (choices contain text and conditions).
   Carries the choice-flag/invisible-default encoding obligation.

5. **S4 conditionals/functions/tunnels — P5.** Completes the supported set to the
   runtime's ceiling. Highest complexity, depends on S2 (expressions) and S3
   (conditional choices share the conditional mechanism).

6. **S5 feature reference document — P6.** Can be drafted at any time from the
   runtime matrix, but its accuracy is only *verifiable* once the supported slices
   (S1-S4) and reject behaviour (S6) exist. Finalise last so it reflects shipped
   reality; draft early as a living artifact.

### Value x Urgency / Effort summary

| Slice | Value | Urgency | Effort | Notes |
|---|---|---|---|---|
| S0 skeleton | 5 | 5 | 1 | spine; derisks everything |
| S6 fail-loud | 5 | 5 | 2 | user's hardest constraint; derisks S1-S4 |
| S1 core flow | 5 | 4 | 2 | first real story |
| S2 vars/expr | 4 | 3 | 3 | CONST inlining obligation |
| S3 choices | 5 | 3 | 3 | unlocks interactivity; weave = highest research risk |
| S4 cond/fn/tunnel | 4 | 2 | 4 | completes ceiling |
| S5 feature doc | 4 | 3 | 1 | first-class deliverable; finalise last |

> Research flag (carried to DESIGN): the feasibility study names **weave resolution**
> (choices + gathers, S3) as the single highest-risk algorithm. DESIGN should treat
> S3 as a candidate spike. This is recorded, not resolved, in DISCUSS.
