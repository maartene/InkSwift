# Slice 01 — Core flow: knots, stitches, diverts, glue

**Feature**: native-ink-compiler | **Release**: 1 (Compile a real linear story) | **Priority**: P3
**Persona**: Maarten | **Job**: job-native-compilation | **Depends on**: S0

## Learning hypothesis
DISPROVES "Ink's flow-control core (named knots/stitches, all divert forms,
glue, newlines) can be compiled to a runtime-consumable story matching the
oracle" if a multi-knot linear story diverges from inklecate.

## Outcome
Compile a linear (choice-free) multi-knot story and play it natively, observing
the same flow inklecate would produce — including relative and anchor diverts
and glue-joined lines.

## Production-real data
- A small real linear story with: 3 knots, 1 stitch, an absolute divert, a
  relative divert (`.^.x`), and a glued line (`<>`). Drawn from / styled after
  The Intercept's linear passages (matrix rows 2-5, 15).
- Oracle: inklecate on the same source.

## Dogfood moment
Maarten compiles the opening (linear) section of his own story in-process and
watches it play through the runtime end to end.

## IN scope (matrix rows: 1, 2, 3, 4, 5, 15)
text output/newlines; knots `=== name`; stitches `= name`; diverts (absolute,
relative pure-ancestor `.^`, anchor `$rN`); relative paths; glue `<>`.

## OUT of scope
- Variables / expressions (S2). Choices / gathers (S3). Conditionals / functions /
  tunnels (S4). Any unsupported construct (S6 rejects it).

## Acceptance (behavioural; Gherkin)
```gherkin
Scenario: A multi-knot linear story compiles and plays, matching the oracle
  Given a .ink source with knots, a stitch, absolute and relative diverts, and glue
  When Maarten compiles it through the in-process compile entry point
  And plays the compiled story through the runtime to its end
  Then the emitted lines are identical to the inklecate-compiled equivalent
  And glue joins lines exactly as inklecate produces them

Scenario: A divert to a named knot lands at the right content
  Given a .ink source whose first knot diverts to a later named knot
  When the story is compiled and played
  Then the runtime continues at the diverted knot's content, matching the oracle
```

## Carpaccio taste tests
- **Thin?** Yes — flow only, no logic/choices. **End-to-end?** Yes — full pipeline.
- **Demonstrable?** Yes — a linear story plays, oracle-matched. **≤1 day?** Yes.
- **Independent value?** Yes — linear stories are publishable on their own.
