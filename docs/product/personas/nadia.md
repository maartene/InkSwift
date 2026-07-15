# Persona: Nadia — Server-Side Swift Developer Running Ink on Linux

**Created**: 2026-07-15 (native-runtime-linux DISCUSS wave)
**Maintainer**: nw-product-owner
**Status**: active

## Role

Server-side / backend Swift developer who runs Swift on **Linux** — Vapor and
Hummingbird services, Discord bots, headless narrative engines, and game
backends. Owns a Linux-first CI pipeline (containers, no Apple hardware in the
loop). Wants to embed Ink interactive-fiction stories inside a Linux service or
a cross-platform library, and to run the whole test suite on a Linux runner.

## Context

- Deploys Swift in Linux containers; a Mac is not part of the build or run path.
- Wants to adopt `SwiftInkRuntime` (the pure-Swift runtime + native compiler)
  precisely *because* it has no JavaScript engine and no external `inklecate`
  binary — those are the two things hardest to ship in a Linux container.
- Discovered that the package does not currently build/behave correctly on
  Linux: source-level CoreFoundation usage in the decoder diverges under
  swift-corelibs-foundation, so `swift build` / `swift test` do not go green.
- Has no macOS-only JavaScript bridge available, so the project's existing
  live-comparison oracle cannot run on her platform.
- Distinct from **Maarten** (who is Apple-platform focused: macOS/iOS/tvOS apps).
  Nadia never ships to an Apple platform — Linux parity is her entire concern.

## Goals

- `git clone` → `swift build` → `swift test` **on Linux** and get a green suite,
  with no Mac and no JavaScript engine anywhere in the loop.
- Play and compile Ink stories on Linux that produce **byte-for-byte identical**
  text and choices to what the same story produces on macOS.
- Trust that a story's numbers and booleans classify identically on Linux — that
  a float stays a float, an int stays an int, and `true` stays a bool — so no
  platform-specific correctness bug hides on a machine she doesn't own.
- Have Linux verification run automatically in CI so parity is guarded on every
  push, not just when someone remembers to test on Linux.

## Frustrations (Push forces)

- "The runtime is *pure Swift* and advertises no native dependencies, yet it
  won't build on Linux because of CoreFoundation number handling in the decoder."
- "There's no oracle I can run on Linux — the comparison harness needs the
  macOS-only JavaScript bridge, so I can't even prove parity locally."
- "CI only runs macOS-arm64. A change can break Linux and nobody notices until I
  pull it into my container build."

## Anxieties (about the new solution)

- "Will number/bool classification silently diverge on Linux — a `2.5` read as
  `2`, or `true` read as `1` — so a story plays differently than on a Mac? That's
  a correctness bug I can't see on the platform I develop the fix on."
- "Without the JS-bridge oracle on Linux, how do I know the committed expected
  outputs I'm comparing against are actually correct, not just self-consistent?"

## Habits (inertia to overcome)

- Trusts "it builds on my Mac" as a proxy for "it builds everywhere" — this
  feature must make Linux a first-class, continuously-verified target so that
  proxy is no longer needed.
- Reaches for a committed golden-file / fixture comparison (a familiar
  server-side testing pattern) rather than a live language-bridge oracle.

## Relationship to Maarten and Raya

Maarten owns the Apple-platform app/toolchain (job-story-playback,
job-native-compilation); Raya authors and unit-tests stories
(job-story-logic-verification). Nadia consumes the **same** runtime and compiler
Maarten helped build, but on a platform he doesn't target. This feature does not
change what the runtime or compiler *do* — it extends their correct-execution
*reach* to Nadia's platform and audience. On a mixed team, Maarten and Nadia are
often two developers on the same codebase who simply build on different OSes.
</invoke>
