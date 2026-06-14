# Slice 04 — Re-enable TheIntercept native-compile end-to-end (ceiling / celebration)

**Feature**: compiler-variable-text | **Release**: 4 (Full ceiling reached) | **Priority**: P1 (the demonstrable payoff)
**Persona**: Maarten | **Job**: job-native-compilation
**Depends on**: slice-01, slice-02, slice-03 (all three deterministic variable-text forms lowered).

## Learning hypothesis
DISPROVES "closing rows 25-27 is sufficient to make the full `TheIntercept.ink`
fixture natively compilable end-to-end." TheIntercept (28 knots, 47 stitches, 21
variables) was the comprehensive ceiling fixture descoped *solely* because line 86
uses a once-only form. If, with the three lowering slices landed, the whole fixture
now compiles natively and plays oracle-identically, the parity gap is provably closed
with zero runtime changes — and shuffle (the one remaining variable-text reject)
still fails loud.

## Outcome
Maarten compiles the full `Tests/InkSwiftTests/TheIntercept.ink` in-process (no
external inklecate, no JS bridge) and plays it through the pure-Swift `Story` along
the committed choice script — line-for-line, choice-for-choice identical to the
inklecate-compiled `.ink.json` oracle. The previously descoped e2e test goes green.

## Production-real data
- `Tests/InkSwiftTests/TheIntercept.ink` — the real comprehensive fixture, including
  the line-86 once-only form `{|I rattle my fingers on the field table.|}`.
- The committed inklecate `.ink.json` oracle for TheIntercept, played through the same
  `Story` along the same choice script (hermetic execution-equivalence, no JS bridge).
- A negative fixture: a TheIntercept-styled scene that adds a shuffle `{~a|b}`,
  confirming shuffle still rejects with a located error after this feature lands.

## Dogfood moment
Maarten deletes the "natively uncompilable — descoped" note from the test suite,
runs the re-enabled TheIntercept native-compile oracle test, and watches it pass —
the whole flagship story now builds and plays without inklecate.

## IN scope (matrix rows 25-27 integration)
Re-enable the descoped `TheIntercept.ink` native-compile end-to-end oracle test;
verify the full fixture compiles in-process and plays oracle-identically; verify
shuffle still rejects with a named, located error (regression guard).

## OUT of scope
- Adding shuffle / RANDOM support (row 28 stays MUST-REJECT).
- Any new variable-text lowering (delivered in slices 01-03).
- Any runtime change. Touching the frozen InkSwift (JS-bridge) module.

## Acceptance (behavioural; Gherkin)
```gherkin
Scenario: TheIntercept compiles natively end-to-end and plays oracle-identically
  Given the full TheIntercept.ink fixture, including its once-only form on line 86
  When Maarten compiles it in-process and plays it along the committed choice script
  Then the emitted lines and presented choices are line-for-line, choice-for-choice
    identical to the inklecate-compiled TheIntercept oracle
  And no external inklecate binary and no JS bridge are invoked

Scenario: The previously descoped TheIntercept native-compile test is green
  Given the TheIntercept native-compile end-to-end oracle test, previously descoped
  When the test suite runs
  Then the test executes and passes (no longer skipped or descoped)

Scenario: Shuffle still rejects with a located error after this feature lands
  Given a TheIntercept-styled scene that uses a shuffle "{~a|b}"
  When the source is compiled
  Then compilation stops with a located error naming "variable-text shuffle" as unsupported
  And no story is produced
```

## Carpaccio taste tests
- **Thin?** Yes — no new lowering; integration + re-enabling one descoped test.
- **End-to-end?** Yes — the most end-to-end slice possible: the full flagship fixture.
- **Demonstrable?** Yes — the descoped test turns green; the headline payoff.
- **≤1 day?** Yes — wiring + assertions once slices 01-03 are in.
- **Independent value?** Yes — proves compiler↔runtime parity on the ceiling fixture.
