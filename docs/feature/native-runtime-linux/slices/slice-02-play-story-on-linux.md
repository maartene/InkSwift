# Slice 02 — Play a Real Story on Linux (Runtime Parity)

**Feature**: native-runtime-linux
**Story**: US-02
**Job**: job-linux-portability
**Size**: ≤ 1 day
**Depends on**: Slice 01 (numbers classify correctly)

## Learning hypothesis

> With numbers classified correctly, the SwiftInkRuntime engine plays a full real
> story on Linux — including SPM `Bundle.module` resource loading and Foundation
> error handling (`localizedDescription`) — line-for-line and choice-for-choice
> identical to a committed macOS fixture.

Validates that the *only* Linux blocker was number classification + resource
loading, not deeper engine behaviour.

## In scope

- `StoryBlueprint(json:)` + `Story` playback of a real committed story on Linux.
- `Bundle.module` resource (`test.ink.json`) resolves under SPM on Linux
  (`InkDecoder.probe()` succeeds).
- The committed-fixture oracle mechanism: expected text + choices captured on
  macOS ground truth, committed, and diffed on Linux.

## Out of scope

- Compiler entry point (Slice 03), CI job (Slice 04).
- Re-deriving number classification (done in Slice 01).
- JS-bridge live comparison (Apple-only; replaced here by committed fixtures).

## Real-story data (not synthetic)

- The Intercept — full playthrough (text + every choice) as the committed fixture.
- The existing `Tests/SwiftInkRuntimeTests/Fixtures` corpus, run on Linux.

## Dogfood moment

Play The Intercept end-to-end on a Linux host via the runtime and diff the entire
transcript (all narrative text + all choices) against the committed macOS fixture —
identical.

## Taste tests

- **Thin?** Yes — playback + resource loading, one real story.
- **End-to-end?** Yes — JSON blueprint → played transcript → golden-file diff.
- **User-visible?** Yes — a real story's text and choices on Linux (US-02 ACs).
- **Independent value?** Yes — Nadia can embed the runtime in a Linux service after this slice, even before the compiler path lands.

## Acceptance criteria

See US-02 in `../feature-delta.md`. Green = The Intercept transcript on Linux
equals the committed macOS fixture, and `Bundle.module` resources resolve.
