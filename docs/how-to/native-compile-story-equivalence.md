# How-to: bring a new Ink story to native↔inklecate execution-equivalence

**Type:** how-to guide (Diataxis). **Audience:** anyone extending the native Ink compiler so a
specific `.ink` story compiles natively and plays *identically* to the inklecate reference.

This is the **probe-driven real-fixing** loop that closed `TheIntercept.ink` (15 increments,
4→80 oracle-matching lines). It exists because the obvious alternative — writing small synthetic
fixtures per construct — **false-greens**: minimal fixtures pass while the real story stays broken,
because real stories combine constructs at a nesting depth the miniatures never reproduce. The
honest gate is the *real story itself*.

## When to use this

- You want a particular complex story to native-compile with execution-equivalence to inklecate.
- You are NOT trying to prove total language parity (that's the supported-construct matrix +
  milestone suites). A story is a *stress test*: passing it proves parity for the constructs and
  combinations it uses.

## Prerequisites: add the story as an oracle fixture

1. Copy the source to `Tests/SwiftInkRuntimeTests/Fixtures/<Story>.ink`.
2. Generate the reference oracle **offline** (inklecate is test-only; CI never invokes it):
   ```
   inklecate -o Tests/SwiftInkRuntimeTests/Fixtures/<Story>.ink.json Tests/SwiftInkRuntimeTests/Fixtures/<Story>.ink
   ```
   `Fixtures/` is bundled via `.process("Fixtures")` in `Package.swift`, so no Package.swift change.
3. Pick a fixed **choice script** (a `[Int]` choosing an option at each choice point) that exercises
   the path you care about.

## The loop (one real blocker at a time)

The instrument is `OracleDiagnostics` + the env-driven `OracleDivergenceProbe`
(`Tests/SwiftInkRuntimeTests/Diagnostics/`). The driver is the **playback first-divergence** report.

1. **Diagnose.** Run the generic probe to see exactly where native first diverges from the oracle:
   ```
   DIAG_STORY=<Story> DIAG_SCRIPT=0,2,1,0 swift test --filter OracleDivergenceProbe
   ```
   It prints: matched-line floor `N`, the first diverging index, the native vs oracle line there,
   and any surviving unresolved dotted `.variableReference`s. That divergence **is** your next task.
2. **Pin it with a ratchet AT.** In an acceptance suite, assert the achieved prefix with
   `OracleDiagnostics.expectNativeMatchesOraclePrefix(story:script:floor:)`. The floor only ever
   rises — a regression that drops below it reds the suite. Bump the floor to your next target
   (just past the current blocker) to make it RED.
3. **RED → GREEN → COMMIT** against the *real* story:
   - **RED:** the bumped ratchet fails for the right business reason (native diverges at the blocker).
   - **GREEN:** fix the actual construct/combination in `Compiler/` (see boundary rules). Re-run the
     probe; set the floor to the **actual achieved** matched-line count (it often jumps past several
     lines that reuse already-fixed constructs). Full suite green.
   - **COMMIT:** through the pre-commit gate (SwiftLint `--strict` + full `swift test`; never
     `--no-verify`).
4. **Re-diagnose and repeat** until the probe reports "NO DIVERGENCE: native == oracle for all M
   lines." Then re-enable / add the story's full e2e AT (compile + play, `#expect(native == oracle)`).

## The two diagnostics — when to use which

- **Playback first-divergence** (`firstDivergence` / `DIAG_INTERCEPT2`-style): the *driver*. Tells you
  the next behavioral blocker. Use it every increment.
- **Structural census** (`structuralCensus` / `DIAG_INTERCEPT`-style): naming-invariant native-vs-oracle
  tree comparison (container/choicePoint/readCount/flag counts + stable-named-content walk). Use it to
  **triage behavioral vs cosmetic** when a divergence is confusing, and to sanity-check that a fix
  closed a *class* of gap rather than one line.

## Boundary rules (non-negotiable)

- Fix in `Compiler/` only. The runtime (`Engine/`, `Decoder/`, `StoryState`) is **REUSE-AS-IS** —
  SwiftLint R1/R3/R5 enforce no `Engine/` import and no `JSONSerialization` from `Compiler/`. If a
  fix seems to need a runtime change, STOP and escalate — it almost never does.
- **Behavioral vs cosmetic (D5).** Correctness is *execution-equivalence along the script*, not
  structural identity. The compiler may emit its own container names/nesting/scaffolding. Only fix
  divergences that change played output; cosmetic shape differences (auto-names, anonymous vs named
  nesting, flag breadth inklecate never reads back) are licensed — don't chase them.

## Why not synthetic minimal fixtures? (the load-bearing lesson)

Minimal per-construct fixtures **false-green**: they pass while the real story stays dead, because
the real failure is the *combination + nesting depth*, not the construct in isolation
(e.g. a choice label nested three levels deep referenced flat; a variable-text lead on a labelled
gather with a loop-back). Drive against the **real story**; let the probe — not your intuition —
say where it breaks. Granular fixtures are still useful as fast regression pins *after* a real fix
lands, but they are not the gate.

## Reference

- Worked example: `TheInterceptDivergenceDiagnostic.swift`, `TheInterceptPlaybackProbe.swift`,
  `Compiler_TheInterceptProgressTests.swift` (the ratchet), and the climb in
  `docs/feature/native-compiler-emission-alignment/feature-delta.md`.
- Design + methodology rationale: ADR-012 (`docs/product/architecture/adr-012-native-inklecate-emission-alignment.md`).
- Evolution archive: `docs/evolution/native-ink-compiler-evolution.md`.
