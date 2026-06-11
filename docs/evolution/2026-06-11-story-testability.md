# Evolution — story-testability

**Date**: 2026-06-11
**Feature ID**: story-testability
**Status**: COMPLETE
**Test result**: 217/217 GREEN (38 suites)
**Milestone**: Milestone7 — 28/28 GREEN

---

## Feature Summary

`story-testability` adds a dedicated testing API to the `Story` facade of `SwiftInkRuntime`, enabling Ink story authors to write deterministic Given-When-Then tests against story logic without replaying fragile choice sequences.

Before this feature, verifying story variable state or visit-count-dependent branches required either reading output text for clues or replaying an exact sequence of `chooseChoice(at:)` calls. A single story edit (adding or reordering a choice) broke all tests that relied on choice indices.

After this feature, a story author can:
- Read variable state directly: `story.getVariable("score")`
- Inject variable preconditions: `story.setVariable("score", to: 10)`
- Read knot visit counts: `story.visitCount(forKnot: "prologue")`
- Drain all output in one call: `story.continueMaximally()`
- Inject knot visit counts for test setup: `story.setVisitCount(forKnot: "prologue", to: 2)` (via `SwiftInkRuntimeTestSupport`)

The feature brings `SwiftInkRuntime` to parity with the reference C# Ink API's `ContinueMaximally()` and adds first-class variable and visit-count introspection that the reference runtime exposes but the prior InkSwift implementation lacked.

### Business Value

The primary persona is **Raya**, a Swift developer and Ink story author. Her story test suite now:
- Replaces brittle choice-replay chains with direct state injection
- Asserts on variable post-conditions (`badge_awarded`, `score`) — not just output text
- Tests visit-count-dependent dialogue branches (`{ prologue > 1: Welcome back! }`) in isolation
- Writes the WHEN step as a single `continueMaximally()` call instead of a 3–4 line `while canContinue` loop

---

## New Public API

### `SwiftInkRuntime` module — `Story` facade

```swift
// Variable introspection (production-safe)
public func getVariable(_ name: String) -> Any?
public func setVariable(_ name: String, to value: some Any)

// Visit count introspection (production-safe)
public func visitCount(forKnot name: String) -> Int

// Output collection (production-safe)
@discardableResult public func continueMaximally() -> String
```

### `SwiftInkRuntimeTestSupport` module — redistributable test helper

```swift
// setVisitCount is test-only — available in story authors' own test suites
// via: import SwiftInkRuntimeTestSupport
extension Story {
    func setVisitCount(forKnot name: String, to count: Int)
}
```

---

## Key Design Decisions

### ST-01: `setVariable` is a pure no-op for unknown keys

If `state.variablesState[name]` does not exist, `setVariable` returns without writing. It does not create a new key. Rationale: the inkjs reference runtime only allows assignment to variables declared with `VAR` in the compiled story. Creating new keys for misspelled names would silently corrupt the variable namespace.

### ST-02: Single `some Any` parameter for `setVariable`

`public func setVariable(_ name: String, to value: some Any)` uses a single `some Any` parameter rather than four per-type overloads (`to value: Int`, `to value: Bool`, etc.). This centralises the `InkValue` bridging logic in one engine accessor. Per-type overloads would duplicate the delegation chain without adding type-safety — Swift's type inference handles `story.setVariable("score", to: 42)` correctly without them.

### ST-03: `continueMaximally` continues looping when errors occur

Errors accumulate in `currentErrors`; the drain loop does not halt. This preserves the equivalence invariant: "Result is identical to manual `while canContinue { output += continue() }` loop." Halting on errors would break this equivalence and diverge from the reference C# `ContinueMaximally()` contract.

### ST-04: `setVisitCount` is test-only via `SwiftInkRuntimeTestSupport` SPM target

Three options were evaluated:
- **Option A** (`#if DEBUG`): boundary is debug/release, not test/production. A production developer building in debug mode could call it accidentally.
- **Option B** (test-target extension file): available only inside InkSwift's own test target. External story authors (Raya's use case) cannot use it in their own projects.
- **Option C** (separate `SwiftInkRuntimeTestSupport` SPM target — **chosen**): redistributable library. Story authors add it as a test dependency in their own `Package.swift`. A production app that accidentally adds it is an explicit, auditable `Package.swift` misconfiguration. Also establishes the correct foundation for future test helpers (`assertOutput`, `setChoiceHistory`, etc.).

---

## Implementation Highlights

### Boolean classification bug fix in `InkDecoder`

A pre-existing bug in `InkDecoder` classified JSON boolean values as `.intValue(0)` and `.intValue(1)` instead of `.boolValue`. The fix used `CFBooleanGetTypeID` to distinguish `NSNumber` booleans from integers before the `intValue` path, adding a `NodeKind.boolValue` case and corresponding `TreeWalker` dispatch. This was discovered during step 01-01 RED phase when boolean variable read-back (`badge_awarded`) returned `0` instead of `true`.

This fix was a prerequisite for `getVariable` returning `Bool` correctly — and also corrected block conditionals that used boolean variables (`{ has_key: ... }`).

### `continueMaximally` implemented in step 01-02 (ahead of schedule)

`continueMaximally()` was originally scoped as step 01-04. During the step 01-02 GREEN phase, the crafter recognised that 3 of the 8 `setVariable` acceptance tests verified `setVariable` effects by reading story output — which required a working `continueMaximally`. The facade-only while-loop implementation was added within the 01-02 commit. All 6 US-04 acceptance tests were GREEN as of that commit. Step 01-04 was closed as merged into 01-02.

### 5-phase TDD per step

Each implementation step followed the methodology: PREPARE → RED_ACCEPTANCE → RED_UNIT → GREEN → COMMIT. The RED phases confirm genuine test failures for business-logic reasons (not setup errors) before implementation begins. Port-to-port discipline was maintained throughout: all acceptance tests drive through the `Story` facade public API, never directly through `InkEngine`.

### `InkEngine.engine` visibility change

`Story.engine` was changed from `private` to `internal` during step 01-03 to allow `@testable import` access from `StoryTestSupport.swift` in the `SwiftInkRuntimeTestSupport` target. This is the minimal visibility change required; `engine` remains invisible to production code outside the module.

### `setVisitCount` guards on structural presence, not visit count

`InkEngine.setVisitCount` guards on `root.namedContent[name] != nil` (structural presence) rather than `visitCounts[name] != nil` (whether the knot has been visited). This was essential to pass the acceptance test that injects a visit count for a knot that has never been visited — the knot exists in the story structure but has no entry in `visitCounts` yet.

---

## Steps Completed

| Step | Name | Status | Commit |
|---|---|---|---|
| 01-01 | `Story.getVariable` + `InkEngine.getVariable` | COMPLETE | `1c12080` |
| 01-02 | `Story.setVariable` + `InkEngine.setVariable` + `continueMaximally` | COMPLETE | `4013eab` |
| 01-03 | `Story.visitCount` + `InkEngine.visitCount/setVisitCount` + `StoryTestSupport.setVisitCount` | COMPLETE | `5446632` |
| 01-04 | `Story.continueMaximally` | MERGED into 01-02 | — |

---

## Files Changed

| File | Change |
|---|---|
| `Sources/SwiftInkRuntime/Facade/Story.swift` | +`getVariable`, `setVariable`, `visitCount`, `continueMaximally` |
| `Sources/SwiftInkRuntime/Engine/InkEngine.swift` | +`getVariable`, `setVariable`, `visitCount`, `setVisitCount`; `engine` visibility `private` → `internal` |
| `Sources/SwiftInkRuntime/Decoder/InkDecoder.swift` | Boolean classification fix (`CFBooleanGetTypeID` check) |
| `Sources/SwiftInkRuntime/Decoder/NodeKind.swift` | +`boolValue` case |
| `Sources/SwiftInkRuntime/Engine/TreeWalker.swift` | +`boolValue` dispatch; step loop flush-defer fix for VAR= lookahead |
| `Sources/SwiftInkRuntimeTestSupport/StoryTestSupport.swift` | `setVisitCount` stub → real delegation |
| `Tests/SwiftInkRuntimeTests/Unit/InkEngineGetVariableTests.swift` | New: 2 unit tests (parametrized bridging + absent key) |
| `Tests/SwiftInkRuntimeTests/Unit/InkEngineSetVariableTests.swift` | New: 3 unit tests (bridging, Bool-before-Int, no-op) |
| `Tests/SwiftInkRuntimeTests/Unit/InkEngineVisitCountTests.swift` | New: 4 unit tests (absent key, stored count, set for present knot, no-op for absent knot) |
| `Tests/SwiftInkRuntimeTests/Unit/NodeKindTests.swift` | +`boolValue` exhaustiveness entry |

---

## Test Coverage

| Suite | Tests | Result |
|---|---|---|
| Milestone7 (story-testability acceptance) | 28 | GREEN |
| InkEngineGetVariableTests | 2 | GREEN |
| InkEngineSetVariableTests | 3 | GREEN |
| InkEngineVisitCountTests | 4 | GREEN |
| All pre-existing suites | 180 | GREEN |
| **Total** | **217** | **GREEN** |

---

## Permanent Artifacts

| Artifact | Path |
|---|---|
| Architecture brief (story-testability section) | `docs/product/architecture/brief.md` — § story-testability |
| DESIGN wave decisions | `docs/feature/story-testability/design/wave-decisions.md` |
| DISTILL wave decisions | `docs/feature/story-testability/distill/wave-decisions.md` |
| User stories | `docs/feature/story-testability/discuss/user-stories.md` |
| Story map | `docs/feature/story-testability/discuss/story-map.md` |
| Journey (YAML) | `docs/ux/story-testability/journey-story-author.yaml` |
| Journey (visual) | `docs/ux/story-testability/journey-story-author-visual.md` |
| Acceptance tests | `Tests/SwiftInkRuntimeTests/Acceptance/Milestone7_StoryTestabilityTests.swift` |
| Test support library | `Sources/SwiftInkRuntimeTestSupport/StoryTestSupport.swift` |
| Execution log | `docs/feature/story-testability/deliver/execution-log.json` |
