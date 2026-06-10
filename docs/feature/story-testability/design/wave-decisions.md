# DESIGN Decisions — story-testability

**Wave**: DESIGN
**Feature**: story-testability
**Date**: 2026-06-10
**Architect**: Morgan (nw-solution-architect)

---

## Key Decisions

- [ST-01] `setVariable` for unknown name is a pure no-op (does not create key): see `docs/product/architecture/brief.md` — story-testability § US-02 Design
- [ST-02] `setVariable` signature uses single `some Any` parameter (not per-type overloads): see brief.md § US-02 Design
- [ST-03] `continueMaximally` continues looping on errors (errors accumulate in `currentErrors`): see brief.md § US-04 Design
- [ST-04] `setVisitCount` is test-only via Option C (separate `SwiftInkRuntimeTestSupport` SPM target): see brief.md § ST-04

---

## Architecture Summary

- Pattern: modular monolith with ports-and-adapters (existing — no change)
- Paradigm: OOP with value-type state (existing — no change)
- Key components affected: `Story` (facade, extended), `InkEngine` (state accessor delegate, extended)
- New target: `Sources/SwiftInkRuntimeTestSupport/StoryTestSupport.swift` (redistributable test-support library)

---

## Reuse Analysis

| Existing Component | File | Overlap | Decision | Justification |
|---|---|---|---|---|
| `Story` (Facade) | `Facade/Story.swift` | Hosts all public API; established delegation pattern | EXTEND | +3 public methods (`getVariable`, `setVariable`, `visitCount`) + 1 discardable (`continueMaximally`); `setVisitCount` excluded from this file |
| `StoryError` | `Facade/Story.swift` | Error taxonomy for throwing methods | NO CHANGE | All four US methods non-throwing (D-02); no new error cases needed |
| `InkEngine` | `Engine/InkEngine.swift` | Owns `state: StoryState`; state mutation delegation pattern | EXTEND | +4 internal accessors: `getVariable`, `setVariable`, `visitCount`, `setVisitCount`; `continueMaximally` is facade-only |
| `StoryState` | `Engine/StoryState.swift` | `variablesState: [String: InkValue]` and `visitCounts: [String: Int]` already present | NO CHANGE | Both dictionaries exist; no new fields required |
| `SwiftInkRuntimeTests` target | `Package.swift` / `Tests/SwiftInkRuntimeTests/` | Existing test target with `@testable import SwiftInkRuntime` | EXTEND | One new file `TestSupport/StoryTestSupport.swift` (Option B for ST-04) |

---

## Technology Stack

- Swift 5.8+ / SPM: existing — no change
- Foundation: existing — no change
- Swift Testing: test target only — existing
- SwiftLint: existing — R4 rule added for `setVisitCount` boundary enforcement

---

## Open Questions from DISCUSS — Resolved

| # | Question | Resolution |
|---|---|---|
| OQ-1 | `setVariable` for unknown name: no-op or create key? | Pure no-op. inkjs reference runtime only writes to declared variables. Creating unknown keys would corrupt the namespace. |
| OQ-2 | `setVariable` signature: `some Any` vs per-type overloads? | Single `some Any`. Centralises bridging; per-type overloads add surface area without type-safety benefit. Consistent with DISCUSS AC. |
| OQ-3 | `continueMaximally` on errors: continue or halt? | Continue looping. Errors accumulate in `currentErrors`. Halting would break the equivalence invariant with the manual `while canContinue` loop. |

---

## Constraints Established

- `setVisitCount` is test-only: Option C — separate `SwiftInkRuntimeTestSupport` SPM target in `Sources/SwiftInkRuntimeTestSupport/StoryTestSupport.swift`. The method does not exist in the `SwiftInkRuntime` module. Story authors add the target as a test dependency to use it in their own projects.
- `setVariable` is production-safe (also needed by host apps for pre-story state injection; e.g., setting player name before story starts)
- `visitCount` (READ) is production-safe (legitimate production use cases exist — e.g., game UI showing visit history)
- `continueMaximally` is production-safe (needed for headless/server-side story rendering)
- `InkValue` must not appear in any public method signature (constraint D-03 — enforced by method signatures above)
- `StoryState` remains `internal` — public API exposes named methods only

---

## Upstream Changes

See `docs/feature/story-testability/design/upstream-changes.md` for the full change notice for product owner review.

Summary: DISCUSS D-04 assumed `setVisitCount` would be a plain `public` method on `Story`. DESIGN changes this: `setVisitCount` is a test-target-only extension (Option B), not part of the `SwiftInkRuntime` public module API.

---

## Method Signatures (Final)

All signatures confirmed no `InkValue` exposure (D-03 satisfied):

```
// Story.swift — public API (production-safe)
public func getVariable(_ name: String) -> Any?
public func setVariable(_ name: String, to value: some Any)
public func visitCount(forKnot name: String) -> Int
@discardableResult public func continueMaximally() -> String

// TestSupport/StoryTestSupport.swift — test target only
// (extension on Story, accessible via @testable import SwiftInkRuntime)
func setVisitCount(forKnot name: String, to count: Int)
```

Note: `setVisitCount` in the test extension does not carry `public` — it is accessible via `@testable import` in the test target, which makes `internal` members visible. No access modifier is needed beyond the `@testable` mechanism.

---

## Slice Sequence (unchanged from DISCUSS D-06)

| Slice | AC | Files Changed |
|---|---|---|
| Slice 01 | `getVariable` | `Story.swift`, `InkEngine.swift` |
| Slice 02 | `setVariable` | `Story.swift`, `InkEngine.swift` |
| Slice 03 | `visitCount` + `setVisitCount` | `Story.swift`, `InkEngine.swift`, `Sources/SwiftInkRuntimeTestSupport/StoryTestSupport.swift` (new), `Package.swift` |
| Slice 04 | `continueMaximally` | `Story.swift` only |
