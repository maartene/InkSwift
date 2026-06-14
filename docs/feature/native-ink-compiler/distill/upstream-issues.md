# DISTILL Upstream Issues — native-ink-compiler (back-propagation)

**Date**: 2026-06-14 | **Wave**: DISTILL | **Raised by**: Final Wave Review Gate (Forge, DEVOPS reviewer)

Two cross-wave consistency items surfaced when the consolidated 4-wave review saw
the whole chain. Neither changes any acceptance scenario or compiler requirement —
both are documentation/CI reconciliations for the platform architect to confirm.
Recorded here per the DISTILL back-propagation contract (do not silently diverge).

---

## UI-1 — KPI #1 execution-equivalence is hermetic / cross-platform (improvement)

**Origin**: DEVOPS `kpi-contracts.yaml` (lines 27-29, 85) + environment matrix frame
KPI #1 as requiring `with-oracle-macos` (the macOS-only InkSwift JS-bridge).

**DISTILL finding**: the implemented oracle compares the **native-compiled** story
against the **committed inklecate `.ink.json`**, both played through the pure-Swift
`Story` runtime along the same choice script (`CompilerOracle.compileAndPlay`). The
compiler acceptance suites import **no `InkSwift`** (verified:
`grep -rl 'import InkSwift' Tests/.../Compiler_*.swift` → none). The comparison is
therefore **hermetic and cross-platform** — it needs no JS-bridge.

**Why it matters**: KPI #1 (the North-Star gate) can run on the `clean` environment
(macOS *and* Linux), widening platform coverage at no cost. The macOS JS-bridge stays
valuable as a **secondary** Level-2 ground-truth cross-check (the existing Milestone
pattern), not a hard requirement for the core gate.

**Resolution — APPLIED (maintainer-confirmed 2026-06-14)**: KPI #1's environment was
relaxed in `kpi-contracts.yaml` (`environment:` → `clean`; `ci_data_source:` reworded),
the DEVOPS environment matrix + monitoring table in `feature-delta.md`,
`devops/wave-decisions.md` (D1, D4), and `environments.yaml` (`clean` is now PRIMARY
+ cross-platform; `with-oracle-macos` is the SECONDARY JS-bridge cross-check).
**Severity**: low (improvement, not a defect).

---

## UI-2 — SwiftLint boundary gate is already LIVE in CI (DEVOPS doc is stale)

**Origin**: DEVOPS D2 / CI outline say the SwiftLint stage should be wired
"alongside the FIRST `Compiler/` slice in DELIVER" and "do not land before first
slice" (decouple config-now from stage-activation-later).

**DISTILL finding**: `.forgejo/workflows/tests.yml` already contains a live `lint`
job (`swiftlint lint --strict --config .swiftlint.yml`, with a brew-install fallback)
— landed in the prior merge (`a2fa4ac`, "add CI lint gate"). `.swiftlint.yml` passes
on the current tree, so the live gate is green and harmless; but it contradicts the
DEVOPS document's stated "activate with first slice" plan.

**Resolution — APPLIED (maintainer-confirmed 2026-06-14), option (A)**: DEVOPS D2 +
the CI/CD outline in `feature-delta.md`, `devops/wave-decisions.md` (D2), and
`environments.yaml` (coexistence + deployment_assumptions) were updated to state the
lint gate is already live and green, with the R5 `custom_rules` path-scoped to
`Compiler/` (so they activate automatically as those files land). **Severity**: low —
doc-vs-reality drift, pre-dates DISTILL; no effect on the acceptance suite.

---

**Impact on DISTILL handoff**: none of the acceptance scenarios depend on the
resolution of UI-1 or UI-2 — the compiler's required behaviour is identical in every
case. The `feature-delta.md` DISTILL sections (DWD-4, Pre-requisites) were reworded to
frame the hermetic-oracle property as a *recommendation* pending DEVOPS confirmation,
removing the unreconciled assertion Forge flagged.
