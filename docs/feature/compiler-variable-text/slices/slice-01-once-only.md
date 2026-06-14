# Slice 01 — Once-only variable-text lowering (`{!a|b}` / `{|x|}`)

**Feature**: compiler-variable-text | **Release**: 1 (Close the TheIntercept blocker) | **Priority**: P1
**Persona**: Maarten | **Job**: job-native-compilation
**Depends on**: native-ink-compiler (delivered) — read→parse→codegen→runtime pipeline + visit-count-switch codegen already exist.

## Learning hypothesis
DISPROVES "the runtime's existing visit-count switch is sufficient to play a
compiler-lowered once-only form." Once-only is the smallest variable-text form and
the exact `TheIntercept.ink` line 86 blocker, so it carries the highest learning
leverage: if the existing switch codegen can express stop-at-last-stage with an empty
trailing stage, the same lowering generalises to sequence and cycle.

## Outcome
Maarten compiles a `.ink` using a once-only form `{!first time|}` or `{|once|}`
in-process and gets back a runnable story that, on first visit, plays the first stage
and on every later visit plays the last (often empty) stage — line-for-line identical
to the inklecate oracle.

## Production-real data
- `{!I rattle my fingers on the field table.|}` — the literal `TheIntercept.ink`
  line 86 once-only construct.
- `{!You knock once.|}` placed inside a sticky-choice loop so it fires once, then
  falls silent on re-entry.
- `{|The lock clicks open.|}` — the bare `{|x|}` once form (no `!`, first-stage then
  empty), verifying both surface spellings lower to the same stop-at-last shape.

## Dogfood moment
Maarten lifts the once-only line out of `TheIntercept.ink`, drops it into a tiny
scene behind a sticky choice, compiles natively, replays the choice three times, and
sees the line appear exactly once — identical to the inklecate-compiled equivalent.

## IN scope (matrix row 27)
Lower the once-only variable-text form (`{!a|b}` and the bare `{|x|}`) into the
read-count-driven visit-count switch the runtime already executes
(stop-at-last-stage / clamp). Compile and play oracle-identical.

## OUT of scope
- Sequence (row 25, slice 02), cycle (row 26, slice 03), shuffle (row 28, stays rejected).
- Re-enabling the full `TheIntercept.ink` e2e test (slice 04).
- Any runtime change — the visit-count switch is already proven.

## Acceptance (behavioural; Gherkin)
```gherkin
Scenario: A once-only form plays its text exactly once, matching the oracle
  Given a .ink source with a once-only form "{!The lock clicks open.|}" behind a sticky choice
  When Maarten compiles it in-process and selects the sticky choice three times
  Then "The lock clicks open." is emitted on the first selection only
  And the emitted output across all three selections is identical to the inklecate oracle

Scenario: The bare once form lowers identically to the "!" spelling
  Given a .ink source using the bare "{|once|}" once-only spelling
  When the source is compiled and played past first and second visits
  Then the playback matches the inklecate-compiled equivalent exactly

Scenario: Shuffle is still rejected (regression guard)
  Given a .ink source using a shuffle "{~a|b}"
  When the source is compiled
  Then compilation stops with a located error naming "variable-text shuffle" as unsupported
```

## Carpaccio taste tests
- **Thin?** Yes — one source form, lowered to an already-proven switch shape.
- **End-to-end?** Yes — source in → runnable story → oracle-identical playback.
- **Demonstrable?** Yes — replay a sticky choice, watch the line fire once.
- **≤1 day?** Yes — single lowering case reusing existing codegen.
- **Independent value?** Yes — closes the exact construct that descoped TheIntercept.
