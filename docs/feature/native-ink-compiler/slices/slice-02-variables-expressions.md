# Slice 02 — Variables & expressions (incl. CONST inlining)

**Feature**: native-ink-compiler | **Release**: 1 (Compile a real linear story) | **Priority**: P3
**Persona**: Maarten | **Job**: job-native-compilation | **Depends on**: S1

## Learning hypothesis
DISPROVES "Ink's value layer (VAR/CONST/temp, assignment, variable-read-in-output,
arithmetic/logic operators, string interpolation) compiles to oracle-matching
output" — and specifically DISPROVES "the compiler correctly performs CONST
inlining, which the runtime assumes was done at compile time" if a CONST-using
story mis-plays.

## Outcome
Compile a linear story that declares and reads variables, computes expressions,
and uses CONSTs; play it natively and observe values rendered identically to the
oracle.

## Production-real data
- A real linear story with: `VAR score = 0`, a CONST set styled after The
  Intercept's 6 CONSTs (`NONE`, `STRAIGHT`, `CHESS`, `CROSSWORD`, `SHOE`, `BUCKET`),
  a `~ temp x`, an assignment, a `{score}` read, an arithmetic expression, and a
  string interpolation. (matrix rows 16-21, 31.)
- Oracle: inklecate on the same source.

## Dogfood moment
Maarten compiles a story whose state (a score, a named constant) drives the text,
and confirms native output equals inklecate's — including the CONST comparisons.

## IN scope (matrix rows: 16, 17, 18, 19, 20, 21, 31)
VAR globals; CONST declarations **with compile-time inlining** (row 17 — the
runtime does NOT do this); temp vars; variable assignment; variable read in
output; arithmetic & logic operators (`+ - * / % == != > < && || !`); string
interpolation.

## OUT of scope
- Choices / gathers (S3). Conditionals (inline/block/switch) and functions (S4).
- Variable-text sequences `{a|b|c}` etc. — UNSUPPORTED, rejected by S6.

## Acceptance (behavioural; Gherkin)
```gherkin
Scenario: A story reading a variable in output matches the oracle
  Given a .ink source declaring "VAR score = 3" and printing "Score: {score}"
  When the story is compiled in-process and played
  Then the runtime emits "Score: 3", matching the inklecate-compiled equivalent

Scenario: A CONST used in a comparison resolves identically to inklecate
  Given a .ink source declaring CONSTs and comparing a variable against one
  When the story is compiled in-process and played
  Then the comparison result and resulting text match the inklecate oracle
  And the compiled story contains the CONST inlined as a literal (no runtime CONST lookup)

Scenario: An arithmetic expression in output matches the oracle
  Given a .ink source printing "{2 + 3 * 4}"
  When compiled and played
  Then the runtime emits "14", matching the oracle
```

## Carpaccio taste tests
- **Thin?** Yes — value layer on top of S1 flow, still no choices.
- **End-to-end?** Yes. **Demonstrable?** Yes — state-driven text, oracle-matched.
- **≤1 day?** Borderline (expressions are broad) — split S2a (VAR/temp/read) from
  S2b (operators + CONST inlining) if it exceeds a day. **Independent value?** Yes.
