# Slice 03 — Compile a Real .ink on Linux (Compiler Parity)

**Feature**: native-runtime-linux
**Story**: US-03
**Job**: job-linux-portability
**Size**: ≤ 1 day
**Depends on**: Slice 02 (runtime plays identically on Linux)

## Learning hypothesis

> The native `InkCompiler.compile(source:)` pipeline (CommentEliminator → InkParser
> → RuntimeObjectEmitter → ContainerNode) is already platform-neutral, so a real
> `.ink` source compiled **in-process on Linux** produces a `StoryBlueprint` that
> plays identically to the same source compiled on macOS — no external inklecate,
> no JS engine.

Extends job-native-compilation's pure-Swift BUILD side onto Linux.

## In scope

- `InkCompiler.compile(source:)` on Linux → `Story` playback → committed fixture diff.
- One real supported-set `.ink` source compiled and played on Linux.

## Out of scope

- Number classification (Slice 01) and runtime playback plumbing (Slice 02).
- CI job (Slice 04).
- Any change to the *supported feature set* — parity only, no new constructs.
- The `.ink` file overload (`compile(fileURL:)`) if still scaffolded — source
  string entry point is sufficient for this slice.

## Real-story data (not synthetic)

- A real supported-subset `.ink` source from the compiler's existing oracle corpus
  (e.g. a knot/stitch/divert/glue/variable-interpolation story already validated on
  macOS against inklecate).

## Dogfood moment

On a Linux host, compile a real `.ink` source string in-process and play the
resulting story; diff the transcript against the committed macOS fixture — identical,
with no inklecate binary present on the machine.

## Taste tests

- **Thin?** Yes — one compile entry point, one real source.
- **End-to-end?** Yes — `.ink` text → compiled blueprint → played transcript → diff.
- **User-visible?** Yes — compiled story text/choices on Linux (US-03 ACs).
- **Independent value?** Yes — completes the pure-Swift compile+run toolchain on Linux for containerized builds.

## Acceptance criteria

See US-03 in `../feature-delta.md`. Green = a real `.ink` compiled in-process on
Linux plays identically to the committed macOS fixture.
