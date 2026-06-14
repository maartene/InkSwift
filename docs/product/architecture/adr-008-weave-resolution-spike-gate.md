# ADR-008: Weave-Resolution Spike Gate

**Status**: Accepted (user-confirmed 2026-06-14)
**Date**: 2026-06-14
**Deciders**: Maarten Engels (project owner), Morgan (nw-solution-architect)
**Feature**: native-ink-compiler

---

## Context

Both the feasibility research and the DISCUSS risk register name **weave resolution** — the algorithm that converts the indentation-based choice/gather graph into a runtime container hierarchy with loose-end divert stitching (`Weave.cs`, ~730 lines in C#) — as the **single highest-risk algorithm** in the compiler. The slice map (S3 / US-04) and the slice-03 brief both flag it for a possible spike before committing the slice plan.

The hard sub-problems (research §4a, Risk 1):
1. Group nested indentation levels into sub-weaves (`ConstructWeaveHierarchyFromIndentation`).
2. During codegen, divert every "loose end" (a choice/gather that did not explicitly divert) to the next gather.
3. Propagate loose ends to ancestor weaves (`PassLooseEndsToAncestors`).
4. Handle the sealed-vs-open distinction (loose ends inside conditionals/sequences propagate only to inner ancestor weaves, not outer ones).

This is the only sub-algorithm whose errors produce **wrong runtime control flow** rather than parse failures — bugs invisible to syntax checks, caught only by running stories against the oracle. Its implementation patterns also influence how the rest of the codegen (container construction, return-address stitching) is structured — so getting it wrong late forces rework.

**Quality attributes for this decision**: Correctness, Risk reduction (de-risk before committing slice estimates), and minimising rework propagation into the codegen design.

---

## Decision

**Gate the S3 slice plan behind a time-boxed weave-resolution spike.** Do NOT commit S3 (and its a/b/c split) sizing until the spike passes its gate.

- **Spike scope**: implement weave hierarchy construction (indentation grouping) + loose-end propagation + gather divert stitching, in isolation, for a small but representative corpus: a flat choice list with a gather; a two-level nested choice/gather; a choice cluster with a labeled gather; and one conditionally-sealed weave (a choice nested inside an inline conditional). Plain/bracketed/sticky/conditional choices are in scope (rows 6-13); the choice-flag/invisible-default *encoding* (row 10, ADR-009-adjacent) is verified as part of the spike's oracle comparison.
- **Oracle**: Level-1 execution-equivalence (the project's existing pattern) — compile the spike corpus with the native weave codegen, play it through `SwiftInkRuntime`, and compare against the inklecate-compiled equivalent played through the same runtime, along fixed choice paths. Level-2 structural JSON comparison is supplementary.
- **Gate (pass/fail)**: the spike PASSES when all four representative corpus stories play **line-for-line and choice-for-choice identical** to the oracle along **representative choice paths** — not combinatorial coverage. Representative = the deterministic always-pick-0 and always-pick-1 paths, plus one varied path per gather-tree depth (mirroring the existing `Milestone5b` non-trivial-playthrough pattern). The goal is detecting *algorithmic* errors (loose-end propagation, sealed-weave confinement), not exhaustive path testing. PASS requires once-only suppression, sticky persistence, and at least one sealed-weave case to match. On PASS, the S3 slice plan (and any a/b/c split) is committed with the spike's container-construction pattern as the codegen template.
- **Time box**: 2-3 days (consistent with the research estimate that the weave algorithm alone needs ~2 weeks to fully port — the spike validates the *pattern*, not the full edge-case surface).
- **Decision authority**: the crafter makes the PASS/FAIL call in consultation with the architect (Morgan). The project owner is informed; re-scoping that changes slice deliverables is owner-visible.
- **FAIL escalation (operational)**: an oracle mismatch unresolved within the time box triggers re-scope into **S3a** (open weaves only: rows 6-13 choices + gathers + read counts, no conditional/sequence sealing) shipped first, and **S3b** (sealed weaves: choice/gather flow gated by conditionals) deferred to a follow-up slice. Residual risk is recorded.
- **WeaveResolver purity (Effect Isolation, principle 12)**: the resolver is a **pure function** — `resolve(ast:) -> (ContainerNode-fragment, looseEnds)` — returning the resolved hierarchy and loose-end list as data, with no IO and no hidden mutation outside its returned value. This contract-shape (pure-function, return-only) is specified at design time and verified in the spike.
- **Sequencing**: the spike runs **before** S3 is sized/committed, but **after** S0 (skeleton) and S1/S2 (it needs the codegen spine and expression support to produce playable output). It is a design-validation spike, not a delivery slice; its code may seed the S3 implementation but is not itself the shippable increment.

---

## Alternatives Considered

### Option B — Design-through (no spike; specify the weave algorithm in DESIGN and implement directly in S3)

Write the weave algorithm specification into the design now and implement it as the first task of S3, relying on oracle tests during S3 RED to catch errors.

**Evaluation**:
- Faster to "start S3" — no separate spike step.
- The highest-risk, rework-propagating algorithm would be discovered-by-failure *inside* a committed slice with committed sizing. Loose-end and sealed/open bugs are subtle (research: "may require several iterations"); discovering them mid-slice invalidates the slice estimate and can cascade into the codegen structure already built around a wrong assumption.
- Contradicts both the research recommendation ("tackle the weave algorithm as a standalone spike before committing to the overall design") and the DISCUSS risk mitigation.

**Rejection rationale**: Concentrates the project's single highest risk inside a committed slice with no de-risking checkpoint, against explicit research and DISCUSS guidance.

### Option C — Full upfront weave implementation in DESIGN (port all of `Weave.cs` before any slice)

Port the entire 730-line algorithm, including all sealed/open edge cases, as a DESIGN deliverable.

**Evaluation**:
- Maximally de-risks weave.
- Violates the simplest-solution and carpaccio principles: it front-loads the most complex component in full before the spine (S0) and linear stories (S1/S2) prove the surrounding pipeline. Much of the full edge-case surface is beyond the bounded supported set's actual usage (The Intercept ceiling does not use deeply pathological nesting).
- DESIGN should design boundaries and gates, not implement the algorithm (architecture owns WHAT, crafter owns HOW).

**Rejection rationale**: Over-builds, inverts the walking-skeleton-first ordering, and crosses the DESIGN/implementation boundary.

---

## Consequences

**Positive**:
- The project's single highest risk is validated against the oracle **before** it can corrupt the S3 slice estimate or the codegen structure.
- The spike's container-construction pattern becomes the proven template for the rest of codegen, reducing rework.
- The gate is objective (oracle line/choice identity), not subjective.

**Negative**:
- Adds a discrete spike step between S2 and S3. Acceptable: it is time-boxed and its output seeds S3, so little work is thrown away.
- If the spike fails within its time box, S3 must be re-scoped (open-weave-first), deferring sealed/open weaves. This is a planned, recorded escalation path — not an unmanaged failure.

**Relationship to ADR-009**: The choice-flag/invisible-default encoding (D6, matrix row 10) is a codegen obligation exercised by the same corpus the spike uses; its omission would surface as a spike oracle failure. The spike therefore also validates that compile-time obligation.
