# Slice 02 — Sequence variable-text lowering (`{a|b|c}`)

**Feature**: compiler-variable-text | **Release**: 2 (General N-stage variable text) | **Priority**: P1
**Persona**: Maarten | **Job**: job-native-compilation
**Depends on**: slice-01 (proves the visit-count-switch lowering path for the simplest case).

## Learning hypothesis
DISPROVES "the once-only lowering generalises to an arbitrary N-stage stop-at-last
sequence." A sequence `{a|b|c}` is the general form once-only is a 2-stage instance
of: advance through stages on each visit, then stick on the last. If the same
read-count switch (`read-count + MIN + ==` + conditional diverts, clamped at the
final stage) plays N stages oracle-identically, the general case is proven.

## Outcome
Maarten compiles a `.ink` using a sequence `{a|b|c}` in-process and gets back a
runnable story that emits `a` on the first visit, `b` on the second, `c` on the third
and every subsequent visit — line-for-line identical to the inklecate oracle.

## Production-real data
- `{red|green|blue}` inside a sticky-choice loop — the canonical 3-stage colour
  sequence; visit four times, expect red, green, blue, blue.
- `{First.|Second.|Third and onwards.}` — prose stages, verifying multi-word stage
  text and the stop-at-last clamp.
- A 2-stage sequence `{Day.|Night.}` re-entered repeatedly, confirming the boundary
  between a 2-stage sequence and the once-only form is handled correctly.

## Dogfood moment
Maarten writes an ambient line `{The corridor is quiet.|The corridor is still quiet.|Nothing has changed.}`
behind a "wait" sticky choice, compiles natively, and watches the description advance
then settle on the final line — identical to inklecate.

## IN scope (matrix row 25)
Lower the sequence variable-text form `{a|b|c}` (N stages, stop-at-last) into the
read-count-driven visit-count switch with a final-stage clamp. Compile and play
oracle-identical.

## OUT of scope
- Cycle (row 26, slice 03), shuffle (row 28, stays rejected).
- Re-enabling `TheIntercept.ink` (slice 04). Any runtime change.

## Acceptance (behavioural; Gherkin)
```gherkin
Scenario: A three-stage sequence advances then clamps, matching the oracle
  Given a .ink source with a sequence "{red|green|blue}" behind a sticky choice
  When Maarten compiles it in-process and selects the choice four times
  Then the emitted stages are "red", "green", "blue", "blue" in order
  And the playback is identical to the inklecate-compiled equivalent

Scenario: A two-stage prose sequence renders each stage then clamps, matching the oracle
  Given a .ink source with a sequence "{Day.|Night.}" re-entered three times
  When the source is compiled and played
  Then the emitted stages are "Day.", "Night.", "Night." matching the oracle

Scenario: Shuffle is still rejected (regression guard)
  Given a .ink source using a shuffle "{~a|b}"
  When the source is compiled
  Then compilation stops with a located error naming "variable-text shuffle" as unsupported
```

## Carpaccio taste tests
- **Thin?** Yes — generalises slice-01's switch shape to N stages; one lowering case.
- **End-to-end?** Yes — source in → runnable story → oracle-identical playback.
- **Demonstrable?** Yes — replay a sticky choice, watch stages advance then settle.
- **≤1 day?** Yes — reuses the proven switch codegen with a stage count.
- **Independent value?** Yes — sequences are the most common variable-text form.
