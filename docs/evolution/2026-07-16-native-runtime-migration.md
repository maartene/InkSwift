# Evolution — native-runtime-migration

**Status**: COMPLETE — the native `SwiftInkRuntime` is now the **recommended** runtime; the JS-bridge `InkStory` API is **deprecated** with a non-breaking warning naming a **v3.0.0** removal, backed by an honest migration guide and a living-backlog parity statement. No JS-bridge behaviour removed; both suites green.
**Date**: 2026-07-16
**Predecessor**: `docs/evolution/2026-07-16-native-runtime-linux.md` — Linux parity made "one recommended runtime for every platform" credible, which is the precondition this feature acts on.

The "nudge" increment: consolidate consumers onto the native runtime **without breaking anyone today**. Scope was deliberately bounded to *deprecate + document*; the actual JS-bridge removal is a separate future feature (breaking major, v3.0.0).

---

## Feature Summary

New job **`job-runtime-consolidation`** (jobs.yaml v4): an existing `InkStory` (v2.x) consumer needs to learn the bridge is legacy, see how their code maps to the native `Story`/`InkCompiler` API, and know honestly what native cannot do yet — so they can decide migrate/stay/wait without a surprise break or an over-claimed "full parity". Personas reused (Maarten primary, Nadia secondary); no new persona.

Four user stories, four thin slices, delivered in dependency order (destinations before the signal):

- **US-04 (01-01)** — `docs/reference/js-bridge-vs-native-parity.md`: honest known-gaps statement; **references** `ink-feature-reference.md` for construct gaps (LIST, RANDOM/SEED_RANDOM, threads, EXTERNAL, shuffle) rather than duplicating them; names the API gaps (Combine observation, tag shape, error handling); documents the living-parity-backlog convention.
- **US-03 (01-02)** — `docs/how-to/migrate-from-js-bridge.md`: `InkStory → Story/InkCompiler` mapping covering 100% of the public surface, incl. the no-native-equivalent Combine gap and the shape changes (tags dict→array, state `String`→`Data`, `getVariable` `JXValue`→`Any?`, added `throws`).
- **US-01 (01-03)** — README repositioned: native recommended for new projects; stale "experimental / first 100 lines" wording removed; JS-bridge reframed as the legacy path.
- **US-02 (01-04)** — the `@available(*, deprecated, message:)` on `InkStory` (ADR-015 Option 1): names v3.0.0 + SwiftInkRuntime + the migration guide. Warning, not error.

### Components Shipped

| Component | Path | Role | Decision |
|---|---|---|---|
| `@available` deprecation on `InkStory` | `Sources/InkSwift/InkStory.swift` | Type-level, `message:` only, no `renamed:` (ADR-015) | **EXTEND** (one non-behavioral annotation) |
| Migration guide | `docs/how-to/migrate-from-js-bridge.md` | Diataxis how-to; api-mapping SSOT | **CREATE NEW** (doc) |
| Parity / known-gaps statement | `docs/reference/js-bridge-vs-native-parity.md` | Diataxis reference; API-gaps SSOT + living backlog | **CREATE NEW** (doc) |
| README reposition | `README.md` | Native recommended; JS-bridge = legacy | **EXTEND** (doc) |
| Migration-guide coverage guard | `Tests/SwiftInkRuntimeTests/Acceptance/DocAccuracy_MigrationGuideCoverageTests.swift` | Asserts the guide covers 100% of `InkStory` public API (KPI-3) | **CREATE NEW** (test) |
| Parity-statement consistency guard | `Tests/SwiftInkRuntimeTests/Acceptance/DocAccuracy_ParityStatementConsistencyTests.swift` | Asserts parity refs the SSOT, names the API gaps, no "full parity" (KPI-4/6) | **CREATE NEW** (test) |

No new module/target/port/adapter; no runtime dependency. Both guard tests are **platform-neutral** (parse files as text, no `import InkSwift`) so the Linux CI job runs them.

---

## The frozen-invariant refinement (the durable design lesson)

Prior architecture locked `InkSwift` as **"frozen — no changes permitted"** (native-runtime D8 / ADR-002). This feature had to touch `InkStory.swift`, so the invariant was **refined, not violated**: `InkSwift` is now **behaviorally frozen** — no logic/signature change; the sole permitted edit is a non-behavioral `@available` annotation (zero runtime effect, JS-bridge still plays identically, still the macOS oracle). `brief.md` frozen-language updated in place; ADR-002 **refined** (ADRs are immutable), recorded in ADR-015's Notes. The freeze's actual intent (behavioural stability + oracle role) is preserved.

Related back-propagation: the DISCUSS `Changed Assumptions` reconciled this feature's deprecate-now/remove-later direction against `native-runtime-linux`'s deliberate "keep the JS-bridge" decision — **continuity, not reversal**: nobody breaks today; consumers get a long, versioned v3.0.0 runway.

---

## Wave compression (right-sizing decisions)

For a docs + one-attribute + two-guard-test feature, two waves were consciously skipped and the ceremony right-sized (maintainer-directed):

- **DEVOPS skipped** — the only guardrail (KPI-5: warning-not-error, suites green) is met **by construction**: there is no `-warnings-as-errors` anywhere (Package.swift / CI / hook verified), and there's no telemetry to instrument (OSS package).
- **Formal DISTILL skipped** — the project's signature execution-equivalence oracle ATs have nothing to bite on (no new runtime behaviour). The two executable **doc-accuracy guards** that *do* fit were folded into DELIVER instead.
- **DELIVER** ran as a single cohesive crafter dispatch (4 DES-monitored steps, trunk commits) rather than the full 8-phase ceremony; L1–L6 refactor / adversarial review / mutation were near-no-ops (mutation is disabled project-wide) and skipped.

---

## Quality State at Finalize

- **macOS**: full suite **356 tests** green (pre-commit gate: SwiftLint boundary rules + `swift test`).
- **Deprecation demonstration (US-02)**: adding the attribute produced **60 deprecation-warning lines** across our own test targets (`InkSwiftTests` + the macOS oracle uses in `SwiftInkRuntimeTests`) — **0 errors**. The warnings are **accepted** (maintainer decision): they are honest (that code uses the deprecated bridge) and they *are* the live US-02 demonstration.
- **Guard tests**: both went RED→GREEN, platform-neutral (run on Linux CI too).
- **Zero `.disabled` ATs** (CLAUDE.md finalize invariant holds).
- **DES integrity**: all 4 steps have complete DES traces (`des-verify-integrity` exit 0).
- Test quality validated by the doc-accuracy guards + the execution-equivalence oracle suite (mutation testing disabled project-wide).

---

## Work Completed (commit history)

| Commit | Step | What |
|---|---|---|
| `518fd45` | 01-01 | Parity / known-gaps statement (US-04) + consistency guard |
| `9e213d9` | 01-02 | `InkStory → Story/InkCompiler` migration guide (US-03) + 100%-coverage guard |
| `8ed5616` | 01-03 | README recommends native, JS-bridge reframed as legacy (US-01) |
| `ab968bc` | 01-04 | `@available` v3.0.0 deprecation warning on `InkStory` (US-02) |

Each commit carries `Step-Id` + `Task-Id: native-runtime-migration` trailers. Waves ran DISCUSS → DESIGN → DELIVER (DEVOPS + formal DISTILL consciously skipped — see Wave compression).

---

## Lessons Learned

1. **Refine locked invariants, don't silently break them.** The "frozen `InkSwift`" contradiction was caught in DESIGN and resolved by narrowing "no changes" to "no *behavioral* changes" — preserving what the freeze actually protected.
2. **The existing suite can be the acceptance vehicle.** With no way to assert a compiler warning in-process, the ~60 deprecation warnings the attribute lights up across our own tests *are* the US-02 demonstration — a RED→GREEN in warning terms, with the suite still green (no `-Werror`).
3. **Right-size the pipeline to the feature.** Skipping DEVOPS (guardrail met by construction) and formal DISTILL (oracle ATs N/A), while keeping two cheap doc-accuracy guards, delivered the value without disproportionate ceremony.
4. **Honesty as a design constraint.** Rejecting `@available(renamed:)` (a misleading cross-module fix-it) and refusing any "full parity" claim kept the nudge trustworthy — the whole point of the feature.
5. **`des-commit` needs the `Task-Id` trailer explicitly** (it appends only `Step-Id`) — pass `Task-Id:` in the commit message body up front to avoid a post-hoc amend.

---

## Deferred / Follow-Up

- **Actual JS-bridge removal** — the breaking v3.0.0 major that deletes the `InkSwift` product; a separate future DISCUSS→…→DELIVER feature. The deprecation shipped here is its advance notice.
- **Closing the documented gaps** — LIST, RANDOM/SEED_RANDOM, threads, EXTERNAL, shuffle `{~a|b}`, and Combine reactive observation. Each is its own increment; per the **living-backlog convention**, the feature that closes a gap must prune it from the parity statement + `ink-feature-reference.md` at finalize.

---

## Source-of-Truth Pointers

- **Deprecation target**: `Sources/InkSwift/InkStory.swift` (the `@available` attribute)
- **ADR**: `docs/product/architecture/adr-015-inkstory-deprecation-mechanics.md` (Accepted, Option 1)
- **Architecture**: `docs/product/architecture/brief.md` → `### native-runtime-migration (Feature Addition)` + the refined frozen invariant (L46/L103)
- **Docs**: `docs/how-to/migrate-from-js-bridge.md`, `docs/reference/js-bridge-vs-native-parity.md`
- **SSOT**: `docs/product/jobs.yaml` (`job-runtime-consolidation`, v4), `docs/product/journeys/native-runtime-migration.yaml`, `docs/product/ink-feature-reference.md` (construct-gap SSOT + maintenance convention)
- **Feature workspace**: `docs/feature/native-runtime-migration/` (feature-delta, slices, design, deliver)
