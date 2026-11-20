# ADR-021: Loose Ends — Emit `done` Only Where inklecate Does

**Status**: Accepted (maintainer, 2026-11-19 — match inklecate). Revised after design review, 2026-11-19 (corrected emission sites). **Implemented in 2.1.5** (steps 02-03, 02-06, 02-05, 02-07; see *Implementation Notes*).
**Date**: 2026-11-19
**Deciders**: Maarten Engels (project owner), Morgan (solution architect)
**Feature**: reference-fidelity-backlog (issue #28, finding F3)
**Amends**: ADR-009 (error model: records that no warning channel exists)

---

## Context

The native compiler appends `.controlCommand("done")` in two places:

- **Every weave.** `WeaveEmitter.lower` ends every weave it lowers with `done`
  (`WeaveEmitter.swift:880`). That covers the root, knots, stitches and nested weave-bearing
  bodies.
- **The root's flat body.** `lowerBodyRoutingWeave` appends `done` to a flat body when
  `terminateFlatBodyWithDone` is true (`RuntimeObjectEmitter.swift:90`). Knot and stitch
  bodies already pass `false` (`RuntimeObjectEmitter.swift:229, 248`), so a **flat** knot or
  stitch gets no `done` today. Only the root's flat body gets one.

So the divergence is confined to **weave-bearing** knot, stitch and nested bodies.

`ConditionalEmitter` depends on the weave's trailing `done`:

- `terminateArm` (`ConditionalEmitter.swift:230-242`) swaps a weave-bearing arm's trailing
  `done` for a rejoin divert. Per inkle/ink#978, a choice inside a conditional must not stop
  the flow.
- `registerContinuation` deliberately leaves the `done` of a rejoin's weave in place
  (`:168-176`). That weave sits at the enclosing knot's level, and swapping it re-enters
  content that has already played. TheIntercept's "sipping at my tea" line would play twice
  (`:170-173`).

inklecate adds `done` only at the top level (`compiler/ParsedHierarchy/Story.cs:193`). A knot
or stitch whose flow runs out gets **no** `done`. inklecate warns instead ("Apparent loose end
exists where the flow runs out…", `FlowBase.cs:398-411`), and the runtime then reports "ran out
of content" (ADR-020). With ADR-020 in place, the native path would otherwise stop silently
where the inklecate path reports an error. That breaks ADR-009's parity rule.

**Warning channel.** `CompileError` (ADR-009) is single-error-then-stop and has no warning
kind. No source file mentions a warning.

## Decision

1. **Emit `done` only where inklecate does**: at the end of the top-level flow.
   - `WeaveEmitter.lower` appends `done` only for the root weave.
   - Knot, stitch and nested weave bodies end without it, so a loose end reaches ADR-020's
     end-of-content diagnosis.
   - The flat-body behaviour (`RuntimeObjectEmitter.swift:90`, root only) already matches.
   - **`ConditionalEmitter` must keep its arm and rejoin semantics** without the trailing
     `done`. `terminateArm` (`:230-242`) can no longer key on a trailing `done`; it must append
     the rejoin divert whenever the arm does not end in control flow. `registerContinuation`
     (`:174`) and the asymmetry described at `:168-176` must be re-derived for a weave without
     `done`: a rejoin weave at knot level must still terminate there, and must not fall
     through into content that has already played.
   - **Regression to protect**: TheIntercept's "sipping at my tea" arm
     (`ConditionalEmitter.swift:170-173`) plays once. Pin it with an AT before the change, in
     addition to the TheIntercept e2e.
2. **The loose-end warning is not surfaced.** InkSwift's compiler has no warning channel.
   The runtime error that follows a loose end on any played path is the observable signal.
   The maintainer agreed (2026-11-19) that a warning channel is valuable but is a **separate
   future feature**, covering compile-time warnings (this one, and the "native compiler reports
   no warnings" backlog) and runtime warnings such as restoring a save from a format version
   that may stop being supported (tracked as #38 and #39). This ADR does not invent one.
3. **Ship it in the same release as ADR-020's epilogue**, so the two paths never disagree on
   `main`.

## Alternatives Considered

- **Keep the implicit `done` and document the difference.** **Rejected** by the maintainer:
  it leaves a native-only silent stop, the failure mode ADR-009 forbids.
- **Reject a loose end at compile time** (an error rather than inklecate's warning).
  **Rejected**: it is stricter than inklecate and refuses stories inklecate compiles. It would
  also need flow analysis to find every loose end statically.
- **Keep `done` in `WeaveEmitter` and strip it in a post-pass for non-root weaves.**
  **Rejected**: it hides the dependency `ConditionalEmitter` has on the `done` instead of
  removing it.
- **Add a warning channel now** (`CompileResult { blueprint, warnings }`). **Deferred** to
  #38/#39: it is a public API addition and needs its own design.

## Consequences

**Positive**
- Native and inklecate paths agree on loose ends.
- Termination moves closer to inklecate's shape (ADR-012 Track A in spirit).

**Negative (release-note callout)**
- A natively compiled story with a loose end **now reports an error** in `currentErrors`
  where it used to stop silently. Its flow is unchanged: the story ends at the same point.
- `ConditionalEmitter`'s arm and rejoin termination is reworked. That is the riskiest part
  of the step; the oracle suite, the TheIntercept e2e and the pinned "sipping" AT gate it.

## Implementation Notes (finalize, 2026-11-20)

Shipped in **2.1.5** together with ADR-020's epilogue, as §3 requires. Turning the epilogue
on exposed native layouts that ran out where inklecate's JSON ends safely, so the work grew
from one step to four:

- **02-03** (U12): a knot- or stitch-level loose end emitted `end`; once `end` discards
  choices that dropped choices inklecate offers. It now emits nothing
  (`WeaveEmitter.FallThrough.runOut`, renamed from `.end` in 06-01).
- **02-06** (U13): `-> DONE` / `-> END` lower to `done` / `end` wherever they are written
  (they used to divert to a nonexistent `DONE` path outside the root); the root's
  conditional rejoins and final gathers reach the root's `done`.
- **02-05**: only the root weave ends in `done`; `terminateArm` no longer swaps a trailing
  `done`. TheIntercept's "sipping at my tea" line was pinned first (`77c2f49`).
- **02-07** (U14): an auto-entered gather of the top-level weave (`- (top)` opening the
  story) gets the root's `done` after its choice points, as C# `Weave.AddRuntimeForGather`
  keeps it inline.

The warning channel (§2) is not built; it is tracked as #38 (compile time) and #39 (runtime).
