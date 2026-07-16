# Evolution — native-runtime-linux

**Status**: COMPLETE — the pure-Swift `SwiftInkRuntime` (runtime + native compiler) builds, tests, and runs on **Linux**, producing output identical to macOS, guarded by a Linux CI job on every push. All four slices (US-01..04) delivered; macOS unaffected.
**Date**: 2026-07-16
**Predecessor**: `docs/evolution/2026-06-01-native-runtime.md` + `docs/evolution/native-ink-compiler-evolution.md` — this feature extends their *reach* (RUN + BUILD sides) to a new platform/audience.

Cross-feature retrospective for `native-runtime-linux`, a parity-only portability feature (same behaviour, new platform). The single most important durable lesson: **two assumptions locked in DISCUSS/DESIGN were falsified during delivery** — see "Falsified Assumptions" below. The end-of-DISTILL consolidated review gate then caught the stale docs those falsifications left behind, which is exactly what that gate is for.

---

## Feature Summary

New persona **Nadia** (server-side Swift developer running Ink on Linux — no Mac, containerised CI) and job **`job-linux-portability`** (jobs.yaml v3). The runtime literally did not compile on Linux; opportunity score 16 (extreme).

The whole blast radius was **one function**: `InkDecoder.classifyNumber` classified JSON numbers/booleans via CoreFoundation type identity (`CFGetTypeID`/`CFBooleanGetTypeID`/`CFNumberGetType`), which is absent under swift-corelibs-foundation — a hard **compile** failure on Linux (not a silent runtime drift, as feared). Every other file compiled.

- **US-01 (walking skeleton)** — portable classification: swap `JSONSerialization`+CF for `JSONDecoder` + a custom `Decodable` (`InkJSONValue`) whose typing is decode-order-driven **Bool → Int → Double**. Platform-stable.
- **US-02** — a real story plays identically on Linux (The Intercept oracle walkthrough).
- **US-03** — a real `.ink` compiles in-process on Linux, identical to the inklecate oracle, no external binary.
- **US-04** — a Linux `swift test` CI job guards parity on every push.

Because the committed-fixture oracle suite is platform-neutral, **US-02 and US-03 came green the moment US-01 made the target compile** — 20 of 28 acceptance files run on Linux and their existing inklecate-fixture assertions *are* the cross-platform parity check.

### Components Shipped

| Component | Path | Role | Decision |
|---|---|---|---|
| `InkJSONValue` + rewritten decode path | `Decoder/InkDecoder.swift` | Portable `JSONDecoder` classification (Bool→Int→Double); node-tree contract unchanged | **EXTEND** (ADR-013 / DD-1) |
| `InkDecoder.probe()` fault-injection | `Decoder/InkDecoder.swift` | Decodes a float/bool/int triple at `Story.init`; throws `decoderProbeFailure` on mis-typing | **EXTEND** (DD-4, Earned Trust) |
| `NativeRuntimeLinux_NumberTypeParityTests` | `Tests/.../Acceptance/` | KPI-3 decode-parity guard (float/bool/int), runs on both platforms | **CREATE NEW** (test) |
| JXKit floor 3.0.0 → **3.6.0** | `Package.swift` | Required for SwiftPM to resolve the graph on Linux | **EXTEND** (unforeseen — see below) |
| `r3_jsondecoder_boundary` | `.swiftlint.yml` | Confines `JSONDecoder` to `Decoder/` (Facade/Compiler scope; Engine ADR-003 exception) | **EXTEND** (DD-5) |
| `test-linux` CI job | `.forgejo/workflows/tests.yml` | `ubuntu-latest` self-hosted Mac-mini, `container: swift:6.3.3`, node-free checkout | **EXTEND** (US-04) |

No new production module; no runtime dependency added; the pure-Swift runtime still needs **no JS engine**.

---

## Falsified Assumptions (the durable lesson)

DISCUSS and DESIGN locked two assumptions that delivery proved wrong. Both were caught — one by the build, one by CI:

1. **"`Package.swift` needs no Linux change" (DESIGN DD-6).** False: JXKit 3.5.1 fails SwiftPM *resolution* on Linux (`invalid access to LICENSE.LGPL`) even though its only consumer (the JS-bridge) is macOS-only — SwiftPM validates the whole dependency graph regardless of platform. A **3.6.0 floor bump** was required. Verified by stashing the bump and reproducing the failure in a clean Linux container.

2. **"The `InkSwift` JS-bridge is Apple-only and Linux CI does not build it."** False: JXKit **3.6.0 ships a Linux JavaScriptCoreGTK backend**, so the JS-bridge *does* build and test on Linux (needs the `libjavascriptcoregtk-4.1-dev` system lib). The correct call was to **keep** it on Linux, not exclude it — excluding the `InkSwift` product would be a **breaking change** for existing Linux consumers (a published open-source package). This was a deliberate maintainer decision over architectural tidiness.

**Lesson**: validate an external dependency's actual platform support (and its transitive resolution behaviour) *before* locking scope assumptions about it. Both falsifications resolved favourably, but the pattern is fragile — the walking-skeleton-first order limited the blast radius.

---

## The CI Bring-up (operational lessons)

A self-hosted Mac-mini Forgejo runner (label `ubuntu-latest`, `container: swift:6.3.3`) was untested; getting `test-linux` green was iterative and each hurdle is now documented in the workflow comments + the feature-delta DEVOPS "Delivery Notes":

- **Docker credential helper** — the runner's `~/.docker/config.json` declared `credsStore: osxkeychain` with no helper on PATH; the public swift image failed to pull. Fixed host-side (remove `credsStore`).
- **No Node in the container** — `actions/checkout` is a JS action; the swift image has no Node and the runner doesn't inject one. Replaced with a plain `git clone` + `git checkout $GITHUB_SHA` (token via `http.extraheader`).
- **JavaScriptCoreGTK system dep** — `apt-get install libjavascriptcoregtk-4.1-dev` before `swift test` (JXKit's Linux backend).
- **Ubuntu mirror fragility** — a confirmed Canonical `ports.ubuntu.com` outage red-ed the apt step; mitigated by dropping the unneeded `noble-backports` suite + `Acquire::Retries=5`. Self-heals when the mirror returns. A pre-baked `swift:6.3.3`+JSC registry image was harvested and proven (green during the outage) but rejected by the registry as too large (~4.5 GB); the maintainer accepts the ~30s per-run apt install for now — durable image deferred.

---

## Quality State at Finalize

- **macOS**: full suite **350 tests / 72 suites** green (pre-commit gate: SwiftLint boundary rules R1/R3/R4/R5 + `swift test`).
- **Linux** (`swift:6.3.3` aarch64): **335 / 71** green — the 15-test delta is the `#if canImport(Combine)` set (Combine is macOS-only), NOT the JS-bridge suite.
- **CI**: `test-macos` + `test-linux` + `lint`, all green on Forgejo.
- **Zero `.disabled` ATs** (CLAUDE.md finalize invariant holds).
- **Consolidated end-of-DISTILL review** (Eclipse/Architect/Forge/Sentinel): all `conditionally_approved`, **0 blockers**; all findings were documentation accuracy (reconciled in `93669fe`).
- Test quality validated by the **execution-equivalence oracle suite** (mutation testing disabled project-wide).

---

## Work Completed (commit history)

| Commit | What |
|---|---|
| `ee289e0` | JSONDecoder scalar classification (ADR-013 / DD-1) — the Linux compile fix |
| `55371a9` | JXKit floor → 3.6.0 for Linux dependency resolution |
| `80452ce` | DISCUSS/DESIGN/DISTILL artifacts + SSOT (persona, journey, job, ADRs, brief) |
| `82789fd` | Linux `test-linux` CI job (US-04) + DEVOPS artifacts |
| `c919007`→`563445a` | CI bring-up: disable macOS/lint, node-free checkout, JSC apt install, drop backports |
| `f212e03` | Re-enable macOS + lint once Linux CI green |
| `0e3c3a0` | DD-4 probe fault-injection + DD-5 R3 JSONDecoder boundary (DELIVER polish) |
| `93669fe` | Reconcile stale JS-bridge/runner assumptions per consolidated review |

Waves ran DISCUSS → DESIGN → DISTILL → DELIVER → DEVOPS (maintainer chose to reach a green Linux build before wiring CI). Each wave's hard gate fired: PO gate (DoR 9/9), architect review (after the principle-12 contract-shape fix), and the consolidated 4-reviewer gate.

---

## Lessons Learned

1. **Falsify dependency assumptions early** — JXKit's Linux resolution + JS-engine backend both contradicted locked assumptions; the build/CI caught them, not the docs.
2. **The consolidated review gate pays off** — all four reviewers *independently* flagged the same JS-bridge stale-text thread across DISCUSS/DESIGN/DEVOPS; per-wave review would have missed the cross-wave inconsistency.
3. **A pre-provisioned dev container can mask CI reality** — the `swiftdev` container had `libjavascriptcoregtk` pre-installed, so the local "cold build" false-greened; the clean CI image exposed the missing system dep.
4. **Not-breaking-consumers beats architectural tidiness** for a published package — keeping the JS-bridge on Linux (vs excluding it) was the right maintainer call.
5. **A defensive Earned-Trust probe** (DD-4) turns a silent cross-platform mis-typing into a loud `Story.init` failure — cheap insurance for a substrate that genuinely differs per platform.

---

## Deferred / Follow-Up

- **Durable CI image** — pre-bake `swift:6.3.3` + `libjavascriptcoregtk-4.1-dev` into a registry image and switch `container:` to it, removing the per-run apt/mirror dependency (blocked once by registry size limit; maintainer accepts the ~30s install for now).

---

## Source-of-Truth Pointers

- **Runtime/decoder**: `Sources/SwiftInkRuntime/Decoder/InkDecoder.swift` (classification + probe)
- **ADRs**: `docs/product/architecture/adr-013-portable-number-bool-classification.md`, `adr-014-cross-platform-equivalence-oracle.md`
- **Architecture**: `docs/product/architecture/brief.md` → `### native-runtime-linux (Feature Addition)`
- **SSOT**: `docs/product/personas/nadia.md`, `docs/product/journeys/linux-portability.yaml`, `docs/product/jobs.yaml` (`job-linux-portability`)
- **CI**: `.forgejo/workflows/tests.yml`; env matrix `docs/feature/native-runtime-linux/environments.yaml`
- **Feature workspace** (preserved for the wave matrix): `docs/feature/native-runtime-linux/`
