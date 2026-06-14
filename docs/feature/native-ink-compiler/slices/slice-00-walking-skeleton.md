# Slice 00 — Walking Skeleton: compile one line of plain text

**Feature**: native-ink-compiler | **Release**: Walking Skeleton | **Priority**: P1
**Persona**: Maarten | **Job**: job-native-compilation

## Learning hypothesis
DISPROVES "the read -> parse -> codegen -> runtime-consumable-story -> execute
pipeline can be wired end to end in pure Swift" if a single line of plain text
cannot be compiled in-process and played to match the inklecate oracle.

## Outcome (what the user can do and observe)
Compile a one-line `.ink` source in-process and play the result in the existing
SwiftInkRuntime, observing the same single line inklecate would have produced.

## Production-real data
- Source file: `Hello, world.` (one line of plain text — the canonical smallest story).
- Oracle: `inklecate /Users/Maarten.Engels/.local/bin/inklecate` compiles the same source.

## Dogfood moment
Maarten replaces a `inklecate hello.ink -o hello.ink.json` + load step with a
single in-process compile-and-play, and sees `Hello, world.` with no external
process in the loop.

## End-to-end scope (touches every pipeline stage)
read source -> parse -> codegen -> runnable story -> runtime plays it -> oracle match.

## IN scope
- Read a single-line plain-text `.ink` source.
- Produce a runnable story the runtime consumes directly (no JSON round-trip required).
- Play it; assert emitted text equals the source line.
- Execution-equivalence oracle assertion against inklecate.

## OUT of scope
- Any Ink construct beyond plain text (knots, diverts, variables, choices) — later slices.
- The secondary JSON output (S2+ / optional).
- Unsupported-feature detection (S6) — a one-line plain-text story triggers none.

## Acceptance (behavioural; Gherkin)
```gherkin
Scenario: A one-line plain-text story compiles and plays, matching the oracle
  Given a .ink source containing exactly "Hello, world."
  When Maarten compiles it through the in-process compile entry point
  And plays the compiled story through the runtime
  Then the runtime emits exactly "Hello, world."
  And no external inklecate binary was invoked during compilation
  And the emitted text is identical to the inklecate-compiled equivalent played through the runtime
```

## Carpaccio taste tests
- **Thin?** Yes — smallest possible input; one pipeline pass.
- **End-to-end?** Yes — exercises all stages from file read to runtime output.
- **Demonstrable?** Yes — visible single line of output, oracle-matched, in one session.
- **≤1 day?** Yes — no language features; pure wiring.
- **Independent value?** Yes — proves the spine; nothing downstream proceeds without it.
