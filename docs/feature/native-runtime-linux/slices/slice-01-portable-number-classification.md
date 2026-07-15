# Slice 01 — Portable Number Classification (WALKING SKELETON)

**Feature**: native-runtime-linux
**Story**: US-01
**Job**: job-linux-portability
**Size**: ≤ 1 day
**Role**: Walking skeleton — the thinnest end-to-end Linux slice. Every later slice
depends on numbers/booleans classifying identically to macOS.

## Learning hypothesis

> A number/bool classification path that does not depend on CoreFoundation type
> identity (`CFGetTypeID` / `CFBooleanGetTypeID` / `CFNumberGetType`) reproduces
> macOS's exact int / float / bool tagging for **real** Ink JSON on Linux.

If false, every downstream story is blocked — this is the riskiest assumption and
the reason the project does not run on Linux today.

## In scope

- `InkDecoder` number/bool classification produces identical int / float / bool
  node tags on Linux and macOS for a committed real-story JSON.
- One committed decode-parity fixture derived from a real story (numbers, floats,
  and at least one boolean).

## Out of scope

- Full story playback (Slice 02), compiler path (Slice 03), CI job (Slice 04).
- The legacy `InkSwift` JS-bridge module (Apple-only — never in scope).
- Prescribing the *implementation* of the portable path (DESIGN owns that; the AC
  only fixes observable classification behaviour).

## Real-story data (not synthetic)

- The Intercept `.ink.json` (28 knots, 47 stitches, 21 variables) — the flagship
  real story already used as the runtime oracle corpus.
- A story fragment carrying `VAR health = 2.5` (float), `VAR score = 2` (int), and
  `VAR alive = true` (bool) — the three classifications that CF-drift breaks.

## Dogfood moment

Decode The Intercept JSON on a Linux host and diff the resulting node type tags
against the committed macOS-captured fixture — zero misclassifications.

## Taste tests

- **Thin?** Yes — one classification concern, one fixture.
- **End-to-end?** Yes — real JSON in, observable typed values out, diffed against a golden file.
- **User-visible?** Yes — a played float renders `2.5`, a bool renders `true` (US-01 ACs).
- **Independent value?** Yes — proves the core blocker is solvable before investing in playback/CI.

## Acceptance criteria

See US-01 in `../feature-delta.md`. Green = float stays float, int stays int,
bool stays bool on Linux, matching the committed macOS fixture exactly.
