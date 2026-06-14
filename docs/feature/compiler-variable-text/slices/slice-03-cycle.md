# Slice 03 — Cycle variable-text lowering (`{&a|b}`)

**Feature**: compiler-variable-text | **Release**: 3 (Wrapping variable text) | **Priority**: P2
**Persona**: Maarten | **Job**: job-native-compilation
**Depends on**: slice-02 (proves the N-stage switch lowering; cycle differs only in wrap vs clamp).

## Learning hypothesis
DISPROVES "the only difference between sequence and cycle lowering is the switch's
wrap-vs-clamp behaviour." A cycle `{&a|b}` advances through stages like a sequence but
wraps to the first stage after the last (modulo the read count over the stage count)
instead of clamping. If the same read-count switch, parameterised to wrap via modulo,
plays oracle-identically, the three deterministic forms (once/sequence/cycle) are
confirmed as one lowering family differing only in the terminal-stage rule.

## Outcome
Maarten compiles a `.ink` using a cycle `{&a|b}` in-process and gets back a runnable
story that emits `a`, `b`, `a`, `b`, … cycling forever on each visit — line-for-line
identical to the inklecate oracle.

## Production-real data
- `{&heads|tails}` inside a sticky-choice loop — the canonical 2-stage cycle; visit
  four times, expect heads, tails, heads, tails.
- `{&Spring|Summer|Autumn|Winter}` — a 4-stage seasonal cycle, verifying the modulo
  wrap over more than two stages.
- `{&The torch flickers.|The torch steadies.}` re-entered five times, confirming the
  wrap repeats cleanly with no off-by-one at the cycle boundary.

## Dogfood moment
Maarten adds an idle animation line `{&The clock ticks.|The clock tocks.}` behind a
"wait" sticky choice, compiles natively, and watches it alternate indefinitely —
identical to inklecate.

## IN scope (matrix row 26)
Lower the cycle variable-text form `{&a|b}` (N stages, wrap via modulo on the read
count) into the read-count-driven visit-count switch. Compile and play oracle-identical.

## OUT of scope
- Once-only (row 27, slice 01), sequence (row 25, slice 02) — delivered earlier.
- Shuffle (row 28, stays rejected). Re-enabling `TheIntercept.ink` (slice 04).
- Any runtime change.

## Acceptance (behavioural; Gherkin)
```gherkin
Scenario: A two-stage cycle wraps forever, matching the oracle
  Given a .ink source with a cycle "{&heads|tails}" behind a sticky choice
  When Maarten compiles it in-process and selects the choice four times
  Then the emitted stages are "heads", "tails", "heads", "tails" in order
  And the playback is identical to the inklecate-compiled equivalent

Scenario: A four-stage cycle wraps via modulo, matching the oracle
  Given a .ink source with a cycle "{&Spring|Summer|Autumn|Winter}" re-entered five times
  When the source is compiled and played
  Then the emitted stages are "Spring", "Summer", "Autumn", "Winter", "Spring" matching the oracle

Scenario: Shuffle is still rejected (regression guard)
  Given a .ink source using a shuffle "{~a|b}"
  When the source is compiled
  Then compilation stops with a located error naming "variable-text shuffle" as unsupported
```

## Carpaccio taste tests
- **Thin?** Yes — same switch shape as slice-02, terminal rule changed to modulo wrap.
- **End-to-end?** Yes — source in → runnable story → oracle-identical playback.
- **Demonstrable?** Yes — replay a sticky choice, watch stages alternate forever.
- **≤1 day?** Yes — one lowering parameter (wrap) over the proven codegen.
- **Independent value?** Yes — cycles complete the deterministic variable-text family.
