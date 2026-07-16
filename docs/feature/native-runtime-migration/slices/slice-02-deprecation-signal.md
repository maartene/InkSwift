# Slice 02 — The JS-bridge API signals it is legacy

**Feature**: native-runtime-migration
**Story**: US-02
**Job**: job-runtime-consolidation
**Size**: ≤ 1 day (~0.5d)
**Role**: "See the legacy signal" — the highest-*reach* touchpoint (it lands at every
consumer's keyboard). (Delivery priority P4 — ships LAST so its message links to the
already-existing migration guide + parity statement and names the runway.)

## Learning hypothesis

> A non-breaking Swift compiler deprecation warning on `InkStory` that names the v3.0.0
> removal and points to `SwiftInkRuntime` + the migration guide will make an existing
> consumer aware the JS-bridge is legacy and start planning migration — *without breaking
> a single existing build*.

If false (the deprecation breaks builds, or names no version/destination), the nudge
either angers consumers or leaves them nudged-into-a-void.

## In scope

- An `@available` deprecation on the JS-bridge `InkStory` public API whose WARNING text
  names removal version **v3.0.0**, names `SwiftInkRuntime`, and references the migration
  guide.
- Guardrail proof: build still succeeds (warning, not error); JS-bridge still plays a
  story; no public API removed; macOS + Linux suites stay green.

## Out of scope

- The exact `@available` attribute spelling / whether to deprecate the type vs each entry
  point / any `renamed:` — DESIGN/DELIVER own the mechanics (DISCUSS fixes the observable
  warning-text CONTENT only).
- Removing any API (that is the future v3.0.0 feature).
- Authoring the guide/parity docs the message points to (Slices 03/04).

## Real-consumer data (not synthetic)

- A consumer app line `let story = InkStory()` (the README's own taught entry point).
- The `removal-version` = `v3.0.0` shared artifact, which must read identically in the
  warning, the migration guide, and the parity statement.

## Dogfood moment

Compile a tiny consumer target that calls `InkStory()` against the deprecated build:
confirm the warning text names v3.0.0 + SwiftInkRuntime + the guide, and the build still
goes green.

## Taste tests

- **Thin?** Yes — one deprecation attribute + its message content.
- **End-to-end?** Yes — a consumer builds and sees the compiler warning.
- **User-visible?** Yes — the deprecation string in Xcode / `swift build` output.
- **Independent value?** Yes — the unmissable legacy signal, the feature's highest-reach nudge.

## Acceptance criteria

See US-02 in `../feature-delta.md`. Green = deprecation warning names v3.0.0 +
SwiftInkRuntime + guide; build succeeds (not an error); no API removed; runway matches
the two docs.
