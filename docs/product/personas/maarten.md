# Persona: Maarten — Swift App Developer Embedding Ink Stories

**Created**: 2026-06-14 (native-ink-compiler DISCUSS wave)
**Maintainer**: nw-product-owner
**Status**: active

## Role

Swift application and game developer who embeds Ink interactive-fiction stories
into Apple-platform apps. Owns the build toolchain for his project and decides
which dependencies ship in his app and which sit in his developer machine setup.

## Context

- Already adopted `SwiftInkRuntime` (the pure-Swift native runtime) so his app
  ships with no JavaScript engine dependency.
- Still depends on the external `inklecate` command-line binary to compile every
  `.ink` source file to `.ink.json` before the runtime can play it.
- Works across macOS, iOS, tvOS targets and increasingly cares about platforms
  where installing and running a separate compiler binary is awkward (CI,
  sandboxed build environments, future Linux/WASM targets).
- Thinks of compilation as a build step that should "just be Swift" now that the
  runtime is.

## Goals

- Keep the entire Ink toolchain — compile and run — inside his Swift project,
  with no external binary to install, version-match, or invoke out-of-process.
- Get a clear, immediate, actionable error when a story uses an Ink feature the
  native runtime cannot play, rather than a silently wrong or crashing story.
- Know precisely which Ink features are supported so he can author within the
  supported set with confidence.

## Frustrations (Push forces)

- "I removed the JS engine from my app, but my build still shells out to a C#
  binary I have to install separately on every machine and CI runner."
- Version drift between `inklecate` output and what the runtime expects is an
  opaque, hard-to-diagnose class of failure.
- No in-process way to compile a story string at runtime (e.g. hot-reload during
  authoring, or generating story content dynamically).

## Anxieties (about the new solution)

- "Will a hand-written Swift compiler produce a story that behaves *identically*
  to what `inklecate` produces? If it diverges silently, I can't trust it."
- "If my story uses a feature the compiler doesn't handle, will it fail loudly,
  or will I ship a broken story?"

## Habits (inertia to overcome)

- Has an established `inklecate file.ink -o file.ink.json` build step wired into
  scripts and CI; any replacement must be at least as simple to invoke.
- Trusts `inklecate` as the ground truth; will want to compare native output
  against it before switching.

## Relationship to Raya

Raya (the story author / test-writer persona, owner of job-story-logic-verification)
authors and unit-tests stories. Maarten owns the toolchain and shipping app.
On a solo project the two personas are often the same human wearing two hats:
Raya writes and verifies the story; Maarten builds and ships it. The compiler
primarily serves Maarten's toolchain-ownership job, and secondarily shortens
Raya's authoring feedback loop (compile in-process, no external binary round-trip).
