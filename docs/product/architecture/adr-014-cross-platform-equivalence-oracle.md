# ADR-014: Cross-Platform Equivalence Oracle — inklecate-Generated Committed Fixtures

**Status**: Accepted (guided-discovery decision locked 2026-07-15)
**Date**: 2026-07-15
**Deciders**: Maarten Engels (project owner), Morgan (nw-solution-architect)
**Feature**: native-runtime-linux (DD-2 + DD-3)

---

## Context

`native-runtime-linux` must prove that `SwiftInkRuntime` plays and compiles Ink
**identically on Linux and macOS** (KPI-2: 100% of the fixture corpus line-for-line /
choice-for-choice identical). This requires a cross-platform correctness *oracle* — a
trusted "what the output should be" that both platforms diff against.

The existing project oracle is the legacy `InkSwift` JS-bridge (`InkStory` over
inkjs via JXKit). The brief's "Correctness" strategy (`brief.md` ~line 185) names it
as the continuously-exercised oracle, and the runtime test target imports it
(`Integration/ may import InkSwift as oracle`, `brief.md` ~line 124). **This oracle is
Apple-only**: JXKit/JavaScriptCore does not ship in a clean Linux container, and the
JS-bridge target is already `.macOS`-conditioned (`Package.swift:67`). It therefore
cannot be the ground truth for a corpus that must be verified *on Linux*.

The repo already has an inklecate-based equivalence practice
(`docs/how-to/native-compile-story-equivalence.md`): inklecate (the canonical C# Ink
reference) generates `.ink.json` fixtures **offline**, committed under
`Tests/SwiftInkRuntimeTests/Fixtures/`, and CI never invokes inklecate. This ADR
builds on and extends that practice into the cross-platform oracle for this feature.

DISCUSS left the oracle strategy open (open question 2); this ADR closes it.

**Quality attributes**: Correctness (the oracle must be authoritative and identical on
both platforms), Portability (must run in a clean Linux container — no JS engine, no
external binary at test time), Testability, Maintainability.

---

## Decision

Adopt a **hybrid, committed-fixture oracle with inklecate as capture-time ground
truth**:

**Ground truth (DD-3)** — **inklecate** (canonical C# Ink) generates the golden
fixtures **at capture time on a dev machine**. Fixtures are **committed** to the repo
and diffed by **both** the macOS and Linux native runtimes. inklecate is a
**capture-time-only** dependency — **never** a Linux-runtime or Linux-CI dependency
(the Linux container stays clean: no JS engine, no inklecate binary). This supersedes
the JS-bridge (`InkStory`/inkjs) as *this feature's* cross-platform oracle and aligns
with the existing equivalence runbook.

**Oracle form (DD-2) — hybrid, two complementary tiers**:

1. **Golden transcript files (primary, black-box)** — the full played text plus the
   choices offered, captured as static committed transcript artifacts, are the primary
   oracle for playback/compile parity (KPI-2). The Linux runtime plays the committed
   story and diffs its transcript line-for-line / choice-for-choice against the
   committed golden transcript. Because the golden file is a static artifact, the
   *same file* feeds the local Linux suite and the Linux CI job — no per-platform
   regeneration (closes the DISCUSS shared-artifact integration risk).
2. **Targeted decode-parity assertions (secondary, white-box-lite)** — a small set of
   float/int/bool decode-parity assertions guard KPI-3 (the highest-risk silent bug,
   ADR-013). These assert that specific known values classify as `.floatValue` /
   `.intValue` / `.boolValue` — the mistyping the golden transcript would only catch
   *if* the value happens to be rendered. They make the silent-typing failure directly
   observable.

**Explicitly NOT adopted**: full decoded-node-tree snapshots. They would expose the
internal `NodeKind`/`ContainerNode` shape (a white-box coupling to implementation
detail), are brittle to any benign internal restructuring, and duplicate what the
transcript + targeted decode asserts already cover behaviourally.

**Corpus (initial)**: The Intercept (full-runtime playback parity, US-02) + one
compiler sample (in-process `.ink` compile parity, US-03) + one float/bool decode
sample (KPI-3 decode-parity, US-01). Exact capture mechanics and any corpus growth
are a DISTILL/DELIVER concern (see Open Questions in the feature-delta).

---

## Alternatives Considered

### Option B — Run the JS-bridge (`InkStory`/inkjs) oracle on Linux

Keep the existing live JS-bridge comparison and run it on the Linux runner.

**Evaluation**: **Impossible for the target environment.** JXKit/JavaScriptCore is
Apple-only and is exactly the JS-engine dependency Nadia adopts `SwiftInkRuntime` to
avoid; the target is a clean Linux container with no JS engine. The JS-bridge target
is already `.macOS`-conditioned and does not build on Linux.

**Rejection rationale**: The oracle cannot run in the environment it must certify.
Non-starter. (The JS-bridge integration tests remain valuable and stay **macOS-only**;
they are simply not the ground truth for the Linux fixture corpus.)

### Option C — Golden transcripts only (no decode-parity assertions)

Rely solely on played-transcript diffs.

**Evaluation**: Simple and mostly sufficient, but it **misses silent mistyping that
does not surface in rendered text** — e.g. a boolean used only in a conditional whose
branch happens to be identical, or an integer never printed. KPI-3 ("zero
misclassifications") is the feature's highest-risk assumption; leaving it only
transitively observable is a gap on exactly the bug the feature exists to prevent.

**Rejection rationale**: Under-covers KPI-3. The targeted decode-parity tier is cheap
and closes the gap; hybrid dominates.

### Option D — Full decoded-node-tree snapshots

Snapshot and diff the entire `ContainerNode`/`NodeKind` tree per fixture.

**Evaluation**: Maximally sensitive, but couples the oracle to the internal AST
representation (white-box), violating the "observable behaviour, not implementation"
principle. Any benign internal refactor (a new `NodeKind` case, a naming change) reds
the suite for non-behavioural reasons — brittle, high-maintenance, and it leaks
internal structure into the test contract.

**Rejection rationale**: Brittle and white-box; couples correctness verification to
implementation detail. The behavioural transcript + targeted decode asserts achieve the
correctness goal without the coupling.

---

## Consequences

**Positive**:
- The oracle runs in a clean Linux container with no JS engine and no inklecate binary
  — it certifies exactly Nadia's target environment (Portability).
- One static golden artifact serves both the local Linux suite and Linux CI (no
  per-platform regeneration; the DISCUSS shared-artifact HIGH risk is structurally
  closed).
- The hybrid form covers both visible divergence (transcript) and invisible mistyping
  (decode-parity), covering KPI-2 and KPI-3 without white-box snapshot brittleness.
- Builds directly on the existing `docs/how-to/native-compile-story-equivalence.md`
  practice and committed-`.ink.json` fixture convention — minimal new machinery.

**Negative**:
- Golden fixtures must be captured/regenerated on a dev machine when the supported Ink
  behaviour legitimately changes; a stale golden diverges from correct output. Mitigated
  by capture being an explicit, documented DELIVER step and inklecate being pinned
  (feature-delta Technology Choices).
- A small new test-support harness (transcript loader + hard-asserting differ) is
  introduced — justified because no existing oracle is both platform-portable *and*
  hard-asserting on a static artifact (the JS-bridge is macOS-only; the
  `OracleDivergenceProbe` diagnostic green-passes even on failure by design). It lives
  in the existing `SwiftInkRuntimeTestSupport` target — **no new SPM target**.

**Back-propagation** (recorded in `brief.md` "Correctness" strategy, ~line 185):
the cross-platform authoritative oracle for the fixture corpus is now
**inklecate-generated committed fixtures** (transcripts + decode-parity); the JS-bridge
`InkStory` remains a **macOS-only** oracle and is **not** the ground truth for this
corpus; `Integration/` JS-bridge oracle imports are `.macOS`-conditioned while Linux
verification is fixture-based.

**Relationship to prior ADRs**: extends the equivalence practice of ADR-012
(native↔inklecate emission alignment) from a macOS diagnostic into the committed,
cross-platform, hard-asserting oracle for Linux parity. Does not change any runtime or
compiler behaviour.
