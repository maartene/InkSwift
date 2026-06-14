# DEVOPS Wave Decisions — native-ink-compiler

**Feature**: native-ink-compiler | **Wave**: DEVOPS | **Architect**: Apex (nw-platform-architect)
**Date**: 2026-06-14 | **Density**: lean (Tier-1 [REF])
**Framing**: SPM **library**, not a deployed service. The cloud-native DEVOPS surface
(k8s, canary/blue-green, runtime observability, autoscaling, IaC) is **N/A** and is
called out as such below rather than invented.

---

## Key Decisions

| # | Decision | Rationale | Source |
|---|---|---|---|
| D1 | **Extend the existing Forgejo workflow** on macos-arm64. **REVISED [DISTILL UI-1, 2026-06-14]**: KPI #1 as implemented compiles natively and compares against the committed inklecate `.ink.json` through the pure-Swift runtime (no `InkSwift` import) — hermetic and cross-platform; it runs on `clean` (macOS + linux). The macOS JS-bridge is the SECONDARY ground-truth cross-check. macos-arm64 stays the CI host (it also runs the secondary check). | `.forgejo/workflows/tests.yml`; DISTILL `upstream-issues.md` UI-1 |
| D2 | **Author `.swiftlint.yml`** with path-scoped `custom_rules` for R1/R3/R5. **REVISED [DISTILL UI-2, 2026-06-14]**: the live `lint` job already landed in `tests.yml` (merge `a2fa4ac`) with a brew-install availability step and passes on the current tree; the R5 rules are path-scoped to `Compiler/`, so they activate automatically as those files land. (The original plan deferred stage activation to the first `Compiler/` slice; it landed early and green instead.) | brief.md R1/R3/R5; DISTILL `upstream-issues.md` UI-2 |
| D3 | **No-inklecate guardrail (KPI #4)** = (a) build-time source guard (production `Compiler/` references no `Process`/inklecate) + (b) a test failing if an inklecate subprocess is spawned during native compile. | Directly instruments the "0 inklecate invocations" KPI; cheap, deterministic, no oracle needed. | feature-delta KPI #4; DDD-10 (inklecate test-only) |
| D4 | **Oracle harness reuse**: committed `.ink.json` fixtures (generated offline via inklecate, REGEN-gated). PRIMARY KPI #1 = native compile vs these fixtures through the pure-Swift runtime (hermetic, cross-platform, UI-1). SECONDARY = the InkSwift JS-bridge cross-check on macos-arm64. inklecate is **not** a CI runtime dependency. | Reuses the established Milestone5b oracle pattern; keeps CI hermetic and offline. | DESIGN Reuse Analysis (oracle harness); DDD-10; DISTILL UI-1 |
| D5 | **Deployment strategy = N/A.** "Release" = git tag + SPM `swift-tools-version`/semver bump; rollback = revert the tag. No rollout/canary/blue-green. | A library has no running instances to roll out or shift traffic across. | environments.yaml deployment_assumptions |
| D6 | **Observability = CI test-gate metrics only.** No runtime telemetry, dashboards, or alerting. The 4 KPIs are CI assertions. | A compiler library emits no runtime signals to observe; instrumenting it would be inventing infrastructure that does not apply. | kpi-contracts.yaml monitoring_model |
| D7 | **Mutation testing DISABLED** (durable project constraint, not a deferral). | Maintainer: no reliable/proven Swift mutation-testing tool exists; Muter was flaky at best after significant effort. Test quality is instead validated by the execution-equivalence oracle suite + code review + the CI boundary gates. Persisted to `CLAUDE.md` with maintainer approval. | maintainer directive; CLAUDE.md `## Mutation Testing Strategy` |
| D8 | **Branching = Trunk-Based Development.** Single `main`; short-lived slice branches; CI gates on every push + pull_request. | Matches the existing `tests.yml` triggers and the slice-per-deliverable cadence. | user decision; existing triggers |
| D9 | **Swift tools 5.6 -> 5.8** raised when the `Compiler/` target lands (not before). | Reconciles `Package.swift` with the brief's 5.8+ baseline; deferred so the current build is undisturbed until needed. | DDD-11; brief tech stack |

---

## Infrastructure Summary

- **CI/CD platform**: Forgejo Actions (existing), one job `test-macos` on `macos-arm64`, triggered on `push` + `pull_request`.
- **Proposed delta (activates with first `Compiler/` slice)**: a SwiftLint boundary-gate step (R1/R3/R5) and a no-inklecate guardrail step, both in the same macOS job. A `swiftlint` install/availability step lands with that delta.
- **Container orchestration**: None (library).
- **IaC**: None (no cloud resources).
- **Observability**: CI test-gate metrics only (4 KPIs as assertions). No runtime telemetry.
- **Oracle**: macOS InkSwift JS-bridge replaying committed `.ink.json` fixtures; inklecate test-only/offline.

## Constraints Established

- R5/R1/R3 SwiftLint boundary gate must pass on every push/PR (authored, verified clean on current tree).
- No-inklecate guardrail must hold for supported builds (0 invocations; KPI #4 hard gate).
- 0% silent wrong output on unsupported input (KPI #2 hard guardrail — must never regress).
- Frozen InkSwift module + JXKit untouched (D8); public `StoryBlueprint(json:)` path unchanged.
- Existing 154-test runtime suite stays green; CI green incrementally per slice.
- Mutation testing remains disabled (durable constraint).

## Upstream Changes

**None.** Every DEVOPS decision aligns with DESIGN (DDD-1..DDD-12) and DISCUSS (D1-D8).
No DESIGN assumption is contradicted, so no `## Changed Assumptions` block and no
`devops/upstream-changes.md` are required. The platform design satisfies R5/oracle/
Swift-version pre-requisites as DESIGN specified them.
