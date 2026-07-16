# ADR-015: `InkStory` Deprecation Mechanics — Type-Level `@available` with `message:`, no `renamed:`

**Status**: Accepted (Option 1, confirmed 2026-07-16)
**Date**: 2026-07-16
**Deciders**: Morgan (nw-solution-architect); Maarten Engels (project owner) — confirmed **Option 1**, 2026-07-16
**Feature**: native-runtime-migration

---

## Context

The `native-runtime-migration` feature (the "nudge" increment) marks the legacy
JS-bridge `InkStory` API as deprecated so that consumers get an unmissable,
non-breaking, versioned legacy signal at their keyboard (US-02). DISCUSS fixed the
observable **warning-text CONTENT** — it must name the removal version **v3.0.0**,
name `SwiftInkRuntime` as the destination, and point to the migration guide
(`docs/how-to/migrate-from-js-bridge.md`). DISCUSS explicitly deferred the **attribute
FORM** to DESIGN (Open Question 1 / Out-of-Scope item).

**Target surface** (`Sources/InkSwift/InkStory.swift`, public members enumerated):
`InkStory` (final class, `ObservableObject`); `init()`; `retainTags`; `loadStory(ink:)`;
`loadStory(json:)`; `currentText`, `canContinue`, `options`, `globalTags`,
`currentErrors`, `currentTags`, `oberservedVariables` (all `@Published`);
`continueStory()`; `chooseChoiceIndex(_:afterChoiceAction:)`; `stateToJSON()`;
`loadState(_:)`; `moveToKnitStitch(_:stitch:)`; `getVariable(_:) -> JXValue`;
`setVariable(_:to:)` ×3 (String/Int/Double); `registerObservedVariable(_:)`;
`deregisterObservedVariable(_:)`; and the `Option` struct (obtained only via
`InkStory.options`).

**Hard guardrail (DISCUSS D-8 / US-02 AC)**: the deprecation MUST be a **warning, not an
error**. Existing consumer builds keep compiling; no public API is removed; the
JS-bridge still plays stories. The `available` platform axis MUST be `*` (unconditional
deprecation), NOT tied to any OS version — the JS-bridge is legacy on every platform,
not from some OS release onward.

**Quality attributes for this decision**: Usability (the consumer notices the signal and
can act on it), Reliability (guardrail — zero build breaks), Correctness (the warning text
matches the shared `removal-version` = v3.0.0 across every surface), Maintainability
(minimal, non-behavioral change to a module that is otherwise frozen — see the
frozen-invariant reconciliation in `brief.md`).

---

## Decision

Adopt **Option 1 — type-level `@available(*, deprecated, message: …)` on `InkStory`,
`message:` only, explicitly NOT `renamed:`.**

```swift
@available(*, deprecated, message: "InkStory (the JavaScriptCore bridge) is legacy and \
will be removed in v3.0.0. Migrate to SwiftInkRuntime's Story / InkCompiler — see the \
migration guide: docs/how-to/migrate-from-js-bridge.md")
public final class InkStory: ObservableObject { … }
```

- **Axis**: `*, deprecated` — unconditional deprecation across all platforms (not
  `introduced/obsoleted`, not OS-versioned). This yields a **warning**, never a build
  error. (A consumer who opts into `-warnings-as-errors` /
  `SWIFT_TREAT_WARNINGS_AS_ERRORS` will see it as an error, but that is the consumer's
  own opt-in, not a break we impose — see Consequences.)
- **`message:` only, NO `renamed:`** — see the cross-module analysis below.
- **Reach**: a type-level deprecation warns at every site that names `InkStory` —
  construction (`InkStory()`), type annotations (`let s: InkStory`), stored properties,
  and function signatures. This covers the DISCUSS driving port ("the warning emitted
  when a consumer builds against `import InkSwift` / `InkStory`").
- **`Option`** (the companion public struct, reachable only through the already-deprecated
  `InkStory.options`) MAY additionally carry the same `@available(*, deprecated, message:)`
  for symmetry, but is not required for reach; DELIVER decides at implementation time
  whether the extra annotation earns its noise. This does not change the FORM decision.

### Cross-module `renamed:` analysis (the crux)

`@available(*, deprecated, renamed: "Story")` is **rejected**. The native replacement
`Story` / `InkCompiler` lives in a **different module** (`SwiftInkRuntime`), while the
attribute is applied in the `InkSwift` module:

1. **The fix-it does not resolve.** `renamed: "Story"` produces a compiler fix-it that
   mechanically rewrites `InkStory` → `Story`, but `Story` is not a symbol in scope at
   the consumer's `import InkSwift` site (they would also need `import SwiftInkRuntime`).
   The fix-it yields code that does not compile — actively misleading.
2. **Module-qualified `renamed: "SwiftInkRuntime.Story"` is still wrong.** Even if the
   fix-it applied, the two APIs are **not drop-in compatible** (per ADR-002 and the US-03
   mapping): `continueStory()` → `continue()`, `chooseChoiceIndex(_:)` →
   `chooseChoice(at:) throws`, `stateToJSON() -> String` → `saveState() throws -> Data`,
   tags `[String:String]` → `[String]`, and Combine observation has **no** native
   equivalent. A `renamed:` fix-it implies a rename; this is a **redesign**, not a rename.
3. **`message:` is the honest form.** It states the legacy status, the v3.0.0 runway, and
   points to the migration guide that carries the real, call-by-call mapping and the gap
   caveats. No false promise of a one-token fix.

---

## Options Considered

### Option 1 — Type-level only, `message:` (no `renamed:`) — **RECOMMENDED**

`@available(*, deprecated, message: …)` on the `InkStory` type alone.

- **Pros**: Simplest change (one attribute, ~3 lines). High reach — warns at every
  construction / type-reference site, which is where a migrating consumer starts.
  Lowest noise. Honest `message:` carries the full DISCUSS-mandated content and the guide
  pointer. Minimal, purely non-behavioral edit to the (behaviorally) frozen module.
- **Cons**: A consumer who only ever passes an existing `InkStory` instance around
  (never names the type, e.g. via a generic or an already-typed property) sees the
  warning only at the original declaration site, not at each member call. In practice the
  type is always named at construction, so this is negligible for this API.
- **Guardrail**: warning, not error. PASS.

### Option 2 — Type + every public entry point

Annotate `InkStory` AND each public method/property (`init`, `loadStory`,
`continueStory`, `chooseChoiceIndex`, `stateToJSON`, `getVariable`, every `@Published`
property, etc.) individually.

- **Pros**: Maximum coverage — warns even when a consumer holds an `InkStory` via a
  typealias or an untyped binding and only touches members. Every call site lights up.
- **Cons**: Verbose and noisy — ~20 attribute sites on a frozen file, cluttering the
  diff and the source. Redundant: once the type is deprecated, the migration decision is
  already surfaced; per-member warnings mostly repeat the same message. The
  `@Published` properties interact awkwardly with per-property attributes. Higher
  maintenance for near-zero marginal reach on this API (the type is essentially always
  named). Risk of "warning fatigue" that trains consumers to blanket-suppress.
- **Guardrail**: warning, not error. PASS (but noisier).

### Option 3 — Type-level with `renamed: "Story"`

`@available(*, deprecated, renamed: "Story")` (optionally module-qualified).

- **Pros**: Single attribute; Xcode surfaces a one-click "fix" affordance.
- **Cons**: **The fix-it is misleading and produces non-compiling / broken code** —
  `Story` is a different module and not API-compatible (see the cross-module analysis).
  This actively violates the feature's honesty principle (the whole feature exists to be
  honest about gaps). `renamed:` also cannot carry a free-text migration-guide pointer
  the way `message:` can.
- **Guardrail**: warning, not error. PASS, but **rejected on honesty/correctness**.

---

## Consequences

**Positive**:
- Minimal, non-behavioral change to `InkStory.swift`: exactly one attribute; zero runtime
  behavior change; the JS-bridge still plays identically and remains the macOS oracle
  (this is what makes the change compatible with the refined "behaviorally frozen"
  invariant — see `brief.md`).
- The warning reaches every consumer who names `InkStory` (i.e. every consumer), naming
  v3.0.0 + SwiftInkRuntime + the guide, satisfying US-02 AC and KPI-2.
- Honest by construction: no false "rename" fix-it that would break code; the consumer is
  routed to the guide that carries the real mapping and the honest gaps.
- The `removal-version` (v3.0.0) is a single string that must read identically in the
  warning, the migration guide, and the parity statement (shared-artifact integrity).

**Negative / trade-offs**:
- A consumer building with **warnings-as-errors** (`-warnings-as-errors` /
  `SWIFT_TREAT_WARNINGS_AS_ERRORS`) will have the deprecation surface as a **compile
  error**. This is the consumer's own opt-in policy, **not a break this feature imposes**;
  the default `swift build` / Xcode build stays green. It is documented in the migration
  guide (suppress via `@available(*, deprecated) `-scoped call or a targeted
  `#warning` policy / build-setting exception) so an affected consumer has an eyes-open
  path. This is the guardrail's known edge case, explicitly accepted.
- Type-level deprecation does not warn on member-only access through an untyped binding
  (Option 2 would). Accepted: negligible for this API shape.

**Enforcement / test obligation** (flows to DISTILL/DELIVER):
- US-02's AC is verified by a **compile that emits the expected warning without
  erroring** — a build-log assertion that the deprecation string is present AND the build
  succeeds (warning, not error). This is a doc-accuracy + compile check, not a runtime
  behavior test (consistent with the feature's mostly-documentation ACs and the
  project-wide "mutation testing disabled" note).
- The `removal-version` consistency (warning ↔ guide ↔ parity statement) is a
  doc-audit obligation (shared artifact `removal-version` = v3.0.0).

---

## Notes

- **Accepted 2026-07-16**: the maintainer confirmed **Option 1** (type-level `@available`
  `message:`, no `renamed:`). No other ADR is superseded; ADR-002 (InkStory frozen) is
  **refined**, not overturned — see the frozen-invariant reconciliation in `brief.md`
  (behaviorally frozen; one non-behavioral annotation permitted).
