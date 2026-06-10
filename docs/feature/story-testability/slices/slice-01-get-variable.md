# Slice Brief: Slice 01 — getVariable

**Feature**: story-testability  
**Slice**: 01  
**Estimated effort**: 0.5 days  
**User story**: US-01  
**Date**: 2026-06-10

---

## Slice Goal

Add `public func getVariable(_ name: String) -> Any?` to `Story`.

After this slice, a story author can assert on the current value of a VAR variable without direct access to engine internals.

---

## Learning Hypothesis

We believe that bridging `InkValue` to Swift native types via `Any?` is sufficient for story author test assertions using `as? Int`, `as? Bool`, `as? String`, `as? Double` casts. If this cast pattern is awkward in practice, we will learn that and may introduce typed overloads in Slice 02.

---

## Carpaccio Taste Test

- **Thin**: yes — read-only, single method, no state mutation
- **End-to-end**: yes — story author can write `#expect(story.getVariable("score") as? Int == 42)` in a real test
- **Verifiable**: yes — story author runs the test and sees it pass or fail; the observable behavior is the return value of `getVariable`
- **Stands alone**: yes — does not depend on Slice 02, 03, or 04

---

## Public API Added

```swift
// Facade/Story.swift
public func getVariable(_ name: String) -> Any?
```

**Bridge rules**:

| InkValue case | Returned Swift type |
|---|---|
| `.int(n)` | `n` as `Int` |
| `.float(f)` | `f` as `Double` |
| `.string(s)` | `s` as `String` |
| `.bool(b)` | `b` as `Bool` |
| `.variablePointer` | `nil` |
| key not in variablesState | `nil` |

---

## Files Changed

- `Sources/SwiftInkRuntime/Facade/Story.swift` — add `getVariable` delegating to InkEngine
- `Sources/SwiftInkRuntime/Engine/InkEngine.swift` — add internal accessor `func variableValue(named:) -> Any?`

---

## Test Fixture Needed

A minimal `.ink.json` fixture with at least one `VAR` of each type (`Int`, `Bool`, `String`) and a knot that assigns them. Suggested file: `slice-story-testability.ink.json` (reused across all four slices).

Sample `.ink` source:
```ink
VAR score = 0
VAR badge_awarded = false
VAR player_name = "unnamed"

-> start

=== start ===
Welcome.
-> DONE

=== reward_check ===
{ score >= 10:
    ~ badge_awarded = true
    You earned the gold badge.
- else:
    Better luck next time.
}
-> DONE

=== set_name ===
~ player_name = "Raya"
Hello, Raya.
-> DONE
```

---

## Acceptance Criteria (Implementation Checklist)

- [ ] `story.getVariable("score")` returns current Int value after `continue()` through an assignment
- [ ] `story.getVariable("badge_awarded")` returns Bool value
- [ ] `story.getVariable("player_name")` returns String value
- [ ] `story.getVariable("nonexistent")` returns nil without throwing
- [ ] `InkValue` type does not appear in the method signature

---

## Swift Testing Examples (model for crafter)

```swift
@Test func `getVariable returns integer value for declared VAR`() throws {
    let story = try makeTestabilityStory()
    try story.moveToKnot("reward_check")
    story.setVariable("score", to: 10) // use after Slice 02; for Slice 01: navigate naturally
    _ = story.continueMaximally()      // use after Slice 04; for Slice 01: manual continue() loop
    #expect(story.getVariable("score") as? Int == 10)
}

@Test func `getVariable returns nil for unknown variable name`() throws {
    let story = try makeTestabilityStory()
    #expect(story.getVariable("nonexistent_variable") == nil)
}
```

Note: The examples above reference methods from later slices for illustration. Slice 01 tests use only `continue()` (existing) and `moveToKnot()` (existing) for setup.

---

## Integration Checkpoints

- Verify `variablesState` is populated after `continue()` through a VAR assignment
- Verify `variablesState` starts empty for a freshly loaded story with no `VAR` declarations (no crash)
- Verify the `InkValue.variablePointer` case returns nil (ref param mechanism — should not be exposed)
