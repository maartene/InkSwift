# Slice 04 — Conditionals, functions, tunnels, ref params, tags

**Feature**: native-ink-compiler | **Release**: 3 (Compile The Intercept ceiling) | **Priority**: P5
**Persona**: Maarten | **Job**: job-native-compilation | **Depends on**: S2, S3

## Learning hypothesis
DISPROVES "the remaining supported control-flow and logic constructs (inline/
block/switch conditionals, functions + inline calls, tunnels, reference
parameters, tags) compile to oracle-matching output, completing the runtime's
supported ceiling" if any of these constructs diverges from inklecate.

## Outcome
Compile a story exercising the complete supported feature set — up to The
Intercept ceiling — and play it natively with output identical to the oracle.

## Production-real data
- A real story styled after The Intercept's advanced passages: inline `{c: a|b}`,
  a block `{cond: ... - else: ...}`, a switch-style conditional dispatching on a
  CONST, a function `=== f(params) ===` with an inline call `{f()}`, a tunnel
  `-> knot ->`, a reference parameter `ref x` (e.g. `raise(ref score)`), and a
  `#tag`. (matrix rows 22-24, 29-35.)
- Oracle: inklecate on the same source.

## Dogfood moment
Maarten compiles a scene of his own story that uses a helper function and a
tunnel, and confirms native play matches inklecate exactly.

## IN scope (matrix rows: 22, 23, 24, 29, 30, 32, 33, 34, 35)
inline conditionals `{c: a|b}`; block conditionals (if/else if); switch-style
conditionals; functions `=== f(params) ===`; inline function calls `{f()}`; tags
`#tag`; save/restore (no compiler action — runtime concern, noted for completeness);
tunnels `-> knot ->`; reference parameters `ref x`.

## OUT of scope
- All unsupported constructs (variable-text sequences/cycles/once/shuffle, threads,
  LIST, RANDOM, externals) — rejected by S6.

## Acceptance (behavioural; Gherkin)
```gherkin
Scenario: An inline conditional renders the correct branch, matching the oracle
  Given a .ink source printing "{visited: again|first time}"
  When compiled and played with the condition false then true
  Then the rendered branch matches the inklecate oracle in each case

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

## Carpaccio taste tests
- **Thin?** Broad — **SPLIT recommended**: S4a conditionals, S4b functions +
  inline calls + ref params, S4c tunnels + tags, if the combined slice exceeds a day.
- **End-to-end?** Yes. **Demonstrable?** Yes — the full ceiling plays, oracle-matched.
- **Independent value?** Yes — completes the supported set; The Intercept compiles natively.
