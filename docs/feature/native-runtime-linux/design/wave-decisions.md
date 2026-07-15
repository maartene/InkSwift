# DESIGN Wave Decisions — native-runtime-linux

**Feature**: native-runtime-linux · **Scope**: Application/components · **Wave**: DESIGN (3 of 6)
**Architect**: Morgan (nw-solution-architect) · **Date**: 2026-07-15
**Interaction mode**: Guide me (guided discovery already conducted; three pivotal
decisions locked and formalized here — not re-opened).

One-liner: make the pure-Swift `SwiftInkRuntime` (runtime + native compiler) build,
test, and run on **Linux**, producing output identical to macOS. Parity only.

---

## Key Decisions

| ID | Decision | ADR |
|---|---|---|
| DD-1 | Portable number/bool classification via `JSONDecoder` + custom `Decodable` (Bool→Int→Double), confined to `Decoder/`. Replaces the CoreFoundation type-identity path (`InkDecoder` `:24-36`, `:123-138`) — unreliable under swift-corelibs-foundation. | ADR-013 |
| DD-2 | Hybrid oracle: golden played-transcript files (primary, KPI-2) + targeted float/int/bool decode-parity assertions (secondary, KPI-3). No node-tree snapshots. | ADR-014 |
| DD-3 | Ground truth = inklecate at capture time; committed fixtures diffed on both platforms; inklecate never a Linux-runtime/CI dependency. Supersedes the JS-bridge oracle for this corpus. | ADR-014 |
| DD-4 | Earned-Trust probe extension: `InkDecoder.probe()` exercises the CF-drift lie (float/bool/int classification) → `decoderProbeFailure` on a mistyping platform. | ADR-013 |
| DD-5 | R3 generalized to "Ink-format JSON decoding confined to `Decoder/`"; `.swiftlint.yml` regex is a DELIVER task, scoped to avoid the ADR-003 `StoryState` save/restore false positive in `Engine/`. | ADR-013 |

---

## Architecture Summary

Fits the existing modular-monolith / ports-and-adapters design with **zero new
production components**. Only production change: EXTEND `InkDecoder` (classify path +
probe). Test-support gains one new type (`FixtureTranscriptOracle`) in the existing
`SwiftInkRuntimeTestSupport` target; fixtures and one CI job are extended. No new
container/topology — the mandatory C4 check is satisfied by the existing L1/L2 plus the
updated L3 InkDecoder annotation (Ink JSON now decoded via `JSONDecoder` + custom
`Decodable`).

Quality attributes (ranked): **Correctness** (platform-identical typing; KPI-3) >
**Portability** (KPI-1) > **Testability/Reliability** > **Maintainability**. Conway:
single maintainer, trivially aligned. Paradigm: object-oriented (unchanged).

---

## Reuse Analysis

Contract shape per **principle 12 (Effect Isolation)** — no component is `unbounded-preservation`.

| Component | File / Location | Decision | Contract shape · universe | Justification |
|---|---|---|---|---|
| `InkDecoder` classify path | `Decoder/InkDecoder.swift` | **EXTEND** | **bounded-change** · Ink-JSON scalar classification → value node-tree | Swap CF type-identity → JSONDecoder + custom Decodable; node-tree contract + consumers unchanged. Not a new decoder. |
| `InkDecoder.probe()` | `Decoder/InkDecoder.swift:38-47` | **EXTEND** | **bounded-change** · startup validation, void/throws | Add float/bool/int fault-injection (DD-4). |
| Fixture corpus / resources | `Tests/SwiftInkRuntimeTests/Fixtures/` | **EXTEND** | **bounded-change** · static committed test data | Add golden transcripts + decode sample; already `.process`-bundled. |
| `FixtureTranscriptOracle` harness | `Sources/SwiftInkRuntimeTestSupport/` | **CREATE NEW** (existing target) | **bounded-change** · test-local: reads static golden, plays story, hard-asserts | Evidence: no existing oracle is both platform-portable AND hard-asserting on a static artifact. JS-bridge oracle is macOS-only (JXKit); `OracleDivergenceProbe` green-passes on failure by design (diagnostic, not assertion). **No new SPM target.** |
| `OracleDiagnostics` / `OracleDivergenceProbe` | `Tests/.../Diagnostics/` | **REUSE AS-IS** | **diagnostic utility** · green-always by design | Retained as incremental diagnosis driver, not the parity gate. |
| Linux CI job | `.forgejo/workflows/tests.yml` | **EXTEND** | **bounded-change** · CI config; pass/fail signal | Add `test-linux` `swift test` job over committed fixtures (US-04). |
| `.swiftlint.yml` R3 rule | `.swiftlint.yml:58-63` | **EXTEND (DELIVER)** | **boundary enforcement** · confines Ink-format JSON decoding to `Decoder/` | Generalize to bind against `JSONDecoder`, scoped past the `Engine/` StoryState exception. |

**Outcome Collision Check**: correctly skipped — `docs/product/outcomes/registry.yaml`
does not exist (registry not bootstrapped). Not bootstrapped.

---

## Technology Stack

| Choice | Version / pin | License | Rationale |
|---|---|---|---|
| `JSONDecoder` + custom `Decodable` | Foundation (bundled) | APSL / Apache 2.0 (Linux) | No new runtime dependency; token-driven typing is platform-stable. |
| Swift toolchain (Linux CI) | floor = `Package.swift` `swift-tools-version`; exact pin = DEVOPS | Apache 2.0 | Build/test on Linux. |
| inklecate (capture-time only) | pinned at capture; inkVersion 21 | MIT | Offline golden-fixture generation; never in Linux runtime/CI. |

No external integrations; no contract tests applicable (only boundary is the static
`.ink.json` format + capture-time inklecate).

---

## Constraints (inherited)

- Solo maintainer; OOP paradigm LOCKED (CLAUDE.md) — not re-decided.
- No new *runtime* dependency; inklecate capture-time-only.
- Forgejo CI (`macos-arm64` today); add a Linux job.
- Swift Testing backtick-name mandate; trunk-based `.disabled`-AT discipline;
  mutation-testing disabled (oracle-suite validation) — all inherited from CLAUDE.md.
- Guardrail: macOS suite + JS-bridge path stay green (no Apple-platform regression).

---

## Upstream Changes

**None to DISCUSS ACs/stories.** The DISCUSS US-01..04 acceptance criteria are
mechanism-neutral (they fix observable int/float/bool behaviour and transcript parity,
not the *how*); DD-1..DD-5 satisfy them without revision. No `upstream-changes.md` for
the PO is required.

Back-propagations to `brief.md` (recorded via the `## Changed Assumptions` convention
in `### native-runtime-linux (Feature Addition)`): Portability (~L189, false→true, DD-1),
Correctness (~L185, cross-platform oracle, DD-3), R3 (~L139, generalized, DD-5),
Module Layout `Integration/` note (~L124, `.macOS`-conditioned). ADR-013 + ADR-014 added
to the ADR Index.

---

## Open Questions (deferred)

1. **DISTILL/DELIVER** — fixture-corpus capture mechanics (transcript format, capture
   command, REGEN discipline).
2. **DELIVER** — `.swiftlint.yml` R3 regex edit (bind `JSONDecoder`, exclude
   `Engine/` StoryState save/restore at `InkEngine.swift:1056`).
3. **DEVOPS** — Swift-on-Linux toolchain version pin + runner/container image (KPI-4).

---

## Handoff

- **DISTILL** (acceptance-designer): hybrid-oracle contract + corpus + fixture capture
  (open Q 1); author ATs `.disabled` per CLAUDE.md.
- **DEVOPS** (platform-architect): Linux runner/toolchain provisioning + pin (open Q 3);
  inklecate stays out of the Linux image. No contract tests needed.
- **DELIVER** (software-crafter): EXTEND `InkDecoder` (ADR-013) + probe (DD-4);
  `FixtureTranscriptOracle`; R3 regex task (open Q 2).
