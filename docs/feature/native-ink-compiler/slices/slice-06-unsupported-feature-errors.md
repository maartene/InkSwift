# Slice 06 — Unsupported-feature error reporting (fail loud, never silent)

**Feature**: native-ink-compiler | **Release**: 4 (No surprises) | **Priority**: P2 (ship detection early)
**Persona**: Maarten | **Job**: job-native-compilation
**Depends on**: detection mechanism is independent; recommended to land alongside S1

## Learning hypothesis
DISPROVES "the compiler reliably detects every unsupported Ink construct and
stops with a clear, located error" — i.e. DISPROVES the user's hardest constraint
("unsupported features should provide a clear error message, not fail silently")
if any unsupported construct compiles to silently-wrong output instead of erroring.

## Outcome
When a `.ink` source uses an Ink feature the runtime cannot play, compilation
stops, no story is produced, and the error names the unsupported construct and
its source location — and (ideally) points to the feature reference (S5).

## Production-real data
- One small `.ink` source per unsupported construct, each isolating a single
  construct (matrix rows 25-28, 36-39):
  variable-text sequence `{a|b|c}`; cycle `{&a|b}`; once-only `{!a|b}`;
  shuffle `{~a|b}`; a thread `<- knot`; a `LIST` declaration; `RANDOM(1,6)` /
  `SEED_RANDOM(...)`; an external function (`EXTERNAL f()` / call `x()`).
- Each fixture is a realistic snippet, not a synthetic token soup.

## Dogfood moment
Maarten pastes a scene that uses a `LIST` (habit from full Ink), compiles, and
immediately sees "LIST declarations are not supported (line 12)" — he fixes it in
seconds instead of discovering a broken story at runtime.

## IN scope (matrix rows: 25, 26, 27, 28, 36, 37, 38, 39)
Detect each unsupported construct during compilation; stop compilation; produce
NO story; emit an error that (a) names the unsupported construct, (b) reports the
source location, and (c) ideally references the supported-feature document.

## OUT of scope
- Compiling any supported feature (S0-S4). Recovering / continuing past the error
  to report multiple diagnostics (a nice-to-have; could be a later enhancement).

## Acceptance (behavioural; Gherkin)
```gherkin
Scenario: A variable-text sequence is rejected with a named, located error
  Given a .ink source using a variable-text sequence "{a|b|c}"
  When Maarten compiles it through the in-process compile entry point
  Then compilation stops without producing a story
  And the error names "variable-text sequence" as unsupported
  And the error reports the source location of the construct

Scenario: A LIST declaration is rejected with a named, located error
  Given a .ink source containing a "LIST" declaration
  When the source is compiled
  Then compilation stops without producing a story
  And the error names "LIST" as unsupported
  And the error reports the source location

Scenario: A thread is rejected with a named, located error
  Given a .ink source using a thread "<- knot"
  When the source is compiled
  Then compilation stops without producing a story
  And the error names "thread" as unsupported with its source location

Scenario: An external function call is rejected with a named, located error
  Given a .ink source declaring an EXTERNAL function
  When the source is compiled
  Then compilation stops without producing a story
  And the error names "external function" as unsupported with its source location

Scenario: No unsupported construct ever compiles silently
  Given a corpus of .ink sources each using one unsupported construct
  When each is compiled
  Then every one stops with an error naming the construct — none produce a story
```

## Carpaccio taste tests
- **Thin?** Yes — detection + error per construct; the detection mechanism is one
  pattern applied across the unsupported set.
- **End-to-end?** Yes — from source in to error out, user-observable.
- **Demonstrable?** Yes — paste unsupported source, see a clear located error.
- **≤1 day?** Yes for the detection mechanism + first few constructs; remaining
  constructs are repetitions of the same pattern.
- **Independent value?** Yes — this is the user's hardest explicit requirement and
  derisks every other slice (nothing unsupported silently slips through).
