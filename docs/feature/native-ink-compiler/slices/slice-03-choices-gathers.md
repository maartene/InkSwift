# Slice 03 — Choices, gathers, read counts (the weave)

**Feature**: native-ink-compiler | **Release**: 2 (Compile an interactive story) | **Priority**: P4
**Persona**: Maarten | **Job**: job-native-compilation | **Depends on**: S1, S2

## Learning hypothesis
DISPROVES "Ink's weave (choices + gathers, with the indentation-driven loose-end
resolution) can be compiled to a runtime-consumable structure matching the oracle"
— the feasibility study names weave resolution the single highest-risk algorithm.
Also DISPROVES "the compiler emits the choice-flag / invisible-default encoding
the runtime assumes was done" (matrix row 10) if a choice mis-plays.

## Outcome
Compile an interactive story with choices and gathers; play it along fixed choice
paths and observe identical choices, choice text, and post-choice flow to the
oracle — including sticky vs once-only behaviour and visit counts.

## Production-real data
- A real interactive story styled after The Intercept: plain `*`, bracketed
  `* [text]`, sticky `+`, and conditional `* {cond}` choices; a multi-level gather
  chain with a labeled gather; a knot read in a `{knot}` visit-count comparison.
  (matrix rows 6-14.)
- Oracle: inklecate on the same source, replayed along the same choice indices.

## Dogfood moment
Maarten compiles the first branching scene of his own story and plays it making
real choices, watching native and oracle output stay in lock-step.

## IN scope (matrix rows: 6, 7, 8, 9, 10, 11, 12, 13, 14)
plain/bracketed/sticky/conditional choices; gathers + labeled gathers; read
counts (knot visit counters); **choice-flag bitfield + invisible-default encoding**
(row 10 — compile-time obligation the runtime assumes).

## OUT of scope
- Conditionals (inline/block/switch), functions, tunnels, ref params (S4).
- Variable-text sequences/cycles/once/shuffle — UNSUPPORTED, rejected by S6.

## Acceptance (behavioural; Gherkin)
```gherkin
Scenario: A story with choices presents identical choices to the oracle
  Given a .ink source with plain, bracketed, and sticky choices and a gather
  When the story is compiled in-process and played
  Then the choices presented at each turn match the inklecate-compiled equivalent
  And selecting a choice index leads to identical subsequent text

Scenario: A once-only choice is suppressed after selection, matching the oracle
  Given a .ink source with a once-only (*) choice that has been selected once
  When the story is replayed to the same point
  Then the once-only choice is no longer presented, matching the oracle

Scenario: A sticky choice remains after selection, matching the oracle
  Given a .ink source with a sticky (+) choice that has been selected once
  When the story is replayed to the same point
  Then the sticky choice is still presented, matching the oracle

Scenario: A conditional choice appears only when its condition holds
  Given a .ink source with a "* {flag} text" choice
  When the story is compiled and played with the flag true and then false
  Then the choice is present when true and absent when false, matching the oracle
```

## Carpaccio taste tests
- **Thin?** Choices+gathers is the broadest single slice — **SPLIT recommended**
  if it exceeds a day: S3a (plain/bracketed/sticky + flag encoding), S3b (gathers +
  labels + loose-end resolution), S3c (conditional choices + read counts).
- **End-to-end?** Yes. **Demonstrable?** Yes — interactive play, oracle-matched.
- **Independent value?** Yes — interactive stories are the majority of real Ink.
- **Risk note:** carries the highest-risk algorithm; DESIGN should consider a
  weave-resolution spike before committing the slice plan.
