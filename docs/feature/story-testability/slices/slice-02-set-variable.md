# Slice Brief: Slice 02 — setVariable

**Feature**: story-testability  
**Slice**: 02  
**Estimated effort**: 0.5 days  
**User story**: US-02  
**Date**: 2026-06-10  
**Depends on**: Slice 01 (type bridging strategy established)

---

## Slice Goal

Add `public func setVariable(_ name: String, to value: some Any)` (or typed overloads — DESIGN choice) to `Story`.

After this slice, a story author can inject GIVEN preconditions by setting variables directly, eliminating fragile choice-replay setup chains.

---

## Learning Hypothesis

We believe that injecting a variable via `setVariable` before `continue()` causes the story's conditional logic to branch correctly — i.e., the engine reads from `variablesState` at runtime, not from a cached snapshot. If the engine caches variable values elsewhere (e.g., in the eval stack snapshot), this slice will surface that as a RED test, and the DESIGN wave will need to address the injection mechanism.

---

## Carpaccio Taste Test

- **Thin**: yes — write-only counterpart to Slice 01; symmetric operation
- **End-to-end**: yes — story author can write a complete GIVEN step with injected variable and verify a changed branch
- **Verifiable**: yes — `#expect(story.getVariable("score") as? Int == 42)` (Slice 01) confirms the write; output assertion confirms the branch
- **Stands alone**: yes — Slice 01 provides read-back verification; Slice 02 adds write

---

## Public API Added

```swift
// Facade/Story.swift — option A (single method)
public func setVariable(_ name: String, to value: some Any)

// OR Facade/Story.swift — option B (typed overloads)
public func setVariable(_ name: String, to value: Int)
public func setVariable(_ name: String, to value: Double)
public func setVariable(_ name: String, to value: String)
public func setVariable(_ name: String, to value: Bool)
```

DESIGN wave chooses between option A and option B based on Swift API design conventions and inkjs reference behaviour. Both are acceptable from a requirements perspective.

**Write rules**:

| Swift type passed | InkValue stored |
|---|---|
| `Int` | `.int(n)` |
| `Double` | `.float(f)` |
| `String` | `.string(s)` |
| `Bool` | `.bool(b)` |
| unknown name | no-op (see wave-decisions.md D-02) |
| other type | no-op or trap — DESIGN decision |

---

## Files Changed

- `Sources/SwiftInkRuntime/Facade/Story.swift` — add `setVariable` delegating to InkEngine
- `Sources/SwiftInkRuntime/Engine/InkEngine.swift` — add internal mutator `func setVariableValue(named:to:)`

---

## Test Fixture

Reuse `slice-story-testability.ink.json` from Slice 01.

---

## Acceptance Criteria (Implementation Checklist)

- [ ] `story.setVariable("score", to: 10)` writes the value; `story.getVariable("score")` returns 10
- [ ] `story.setVariable("badge_awarded", to: true)` enables the `badge_awarded == true` branch in `continueMaximally()`
- [ ] `story.setVariable("player_name", to: "Raya")` causes output to contain "Raya"
- [ ] Setting an unknown variable name does not throw
- [ ] Setting a variable does not affect `canContinue`, `currentChoices`, or execution position
- [ ] `InkValue` type does not appear in the method signature

---

## Swift Testing Examples (model for crafter)

```swift
@Test func `setVariable changes output of conditional text`() throws {
    let story = try makeTestabilityStory()
    try story.moveToKnot("reward_check")
    story.setVariable("score", to: 10)
    var output = ""
    while story.canContinue { output += story.`continue`() }
    #expect(output.contains("You earned the gold badge."))
}

@Test func `setVariable read-back confirms value was stored`() throws {
    let story = try makeTestabilityStory()
    story.setVariable("score", to: 42)
    #expect(story.getVariable("score") as? Int == 42)
}

@Test func `setVariable with unknown name does not throw`() throws {
    let story = try makeTestabilityStory()
    story.setVariable("nonexistent_variable", to: 99)
    // No throw expected; getVariable returns nil
    #expect(story.getVariable("nonexistent_variable") == nil)
}
```

---

## Integration Checkpoints

- Verify that setting a variable after `moveToKnot` (which resets execution stacks but preserves `variablesState`) works correctly — the value must survive the jump
- Verify that setting a variable before `moveToKnot` also works — variables are preserved across jumps
- Verify that `setVariable` does not accidentally reset `isEnded`, `canContinue`, or `currentChoices`
- Verify the type round-trip: set Int 42, get back Int 42 (not Double 42.0)
