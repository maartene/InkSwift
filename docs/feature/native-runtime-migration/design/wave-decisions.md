# DESIGN Decisions — native-runtime-migration

> Application scope (@nw-solution-architect / Morgan), propose mode. Thin-architecture
> feature: one non-behavioral `@available` attribute + two Diataxis docs + a README
> reposition. Full narrative in `../feature-delta.md` (`## Wave: DESIGN` sections),
> `docs/product/architecture/brief.md` (`### native-runtime-migration (Feature Addition)`),
> and `docs/product/architecture/adr-015-inkstory-deprecation-mechanics.md`.

## Key Decisions

- **[DD-1] `@available` FORM = type-level `message:`, NO `renamed:`** — `@available(*,
  deprecated, message: …)` on the `InkStory` type; message names v3.0.0 + SwiftInkRuntime
  + the migration guide. Rejects `renamed:` (native `Story` is a different module and not
  API-compatible → misleading non-compiling fix-it) and per-member annotation (noise,
  negligible extra reach). **Status: Accepted — maintainer confirmed Option 1 (2026-07-16).** (ADR-015)
- **[DD-2] Axis `*, deprecated` → warning, not error** — unconditional, all-platform.
  Guardrail PASS. Warnings-as-errors consumers see an error by their own opt-in; suppression
  documented in the guide. (see: adr-015 Consequences)
- **[DD-3] `InkSwift` invariant refined to "behaviorally frozen"** — narrows the
  `native-runtime` D8 / ADR-002 "no changes permitted" to "no behavioral change; one
  non-behavioral `@available` annotation permitted". `brief.md` L46/L103 updated in place;
  ADR-002 refined, not edited. (see: brief.md Changed Assumptions table)
- **[DD-4] Diataxis doc homes confirmed** — how-to `docs/how-to/migrate-from-js-bridge.md`
  (api-mapping SSOT); reference `docs/reference/js-bridge-vs-native-parity.md` (API-gaps
  SSOT, references `ink-feature-reference.md` for construct gaps); README links both. No
  separate playbook doc.
- **[DD-5] Outcome Collision Check N/A** — no `docs/product/outcomes/registry.yaml`.

## Architecture Summary

- **Pattern**: unchanged — two parallel, non-layered modules (`InkSwift` JS-bridge,
  `SwiftInkRuntime` native). This feature adds no component, port, or adapter.
- **Paradigm**: object-oriented (inherited from CLAUDE.md — not re-decided).
- **Key components touched**: `InkStory` (EXTEND, one attribute); two new docs; README.

## Reuse Analysis

| Existing Component | File | Overlap | Decision | Justification |
|---|---|---|---|---|
| `InkStory` (public type) | `Sources/InkSwift/InkStory.swift` | The API being deprecated | **EXTEND** | Attach `@available` (~3 lines); universe ∅ (zero runtime effect). A new type is absurd — signal legacy on the existing type in place. |
| `Option` (public struct) | `Sources/InkSwift/InkStory.swift` | Companion type via `InkStory.options` | **EXTEND (optional)** | Same attribute for symmetry; DELIVER decides. Reach-neutral. |
| README | `README.md` | Runtime recommendation | **EXTEND** | Reposition + link the two docs. Content authored in DELIVER. |
| Migration guide | `docs/how-to/migrate-from-js-bridge.md` | — | **CREATE NEW (doc, not code)** | Diataxis how-to; no module/target/port. |
| Parity statement | `docs/reference/js-bridge-vs-native-parity.md` | — | **CREATE NEW (doc, not code)** | Diataxis reference; API-gaps SSOT; references construct-gap SSOT. |

Zero unjustified CREATE NEW.

## Technology Stack

- **Swift `@available(*, deprecated, message:)`** — native, zero-dependency deprecation;
  warning honored by `swift build` + Xcode.
- **Markdown Diataxis docs** — no tooling change.
- No new runtime or dev dependency.

## Constraints Established

- Deprecation is a **warning, not an error**; no public API removed; JS-bridge stays fully
  functional and remains the macOS oracle (guardrail D-8).
- `removal-version` = **v3.0.0** must read identically across the warning, migration guide,
  and parity statement (shared-artifact integrity).
- `InkSwift` is **behaviorally frozen** — the `@available` annotation is the only permitted
  edit; no logic/signature change.
- US-02 verified by a **compile that emits the expected warning without erroring**
  (build-log assertion), not a runtime behavior test (mutation testing disabled project-wide).

## Upstream Changes

- **None to DISCUSS stories/ACs.** The frozen-invariant refinement (DD-3) required no
  story/AC change — the US-02 guardrail already scoped it. No `design/upstream-changes.md`
  created.

## Open Questions (→ DISTILL/DELIVER)

1. ~~Flip ADR-015 Proposed → Accepted~~ **Done** — maintainer confirmed Option 1 (2026-07-16); ADR-015 Accepted.
2. Whether `Option` also carries the attribute (DELIVER).
3. Warnings-as-errors suppression wording in the guide (DELIVER).
4. US-02 AT as a build-log warning-present + build-succeeds assertion (DISTILL).

## Peer Review

Per-wave Eclipse/architect review **skipped** (propose-mode + maintainer confirmation
covers the one contested decision; the mandatory consolidated 4-reviewer gate fires at end
of DISTILL). No trigger (no contested ADR beyond the one being confirmed, no novel pattern,
no perf/security boundary change).
