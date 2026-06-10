# Slice Brief: Slice 04 — continueMaximally

**Feature**: story-testability  
**Slice**: 04  
**Estimated effort**: 0.5 days  
**User story**: US-04  
**Date**: 2026-06-10  
**Depends on**: None (uses only existing `continue()`)

---

## Slice Goal

Add `@discardableResult public func continueMaximally() -> String` to `Story`.

After this slice, a story author can execute the WHEN step of a GWT test in a single line, collecting all output to the next choice point. The manual `while canContinue { output += continue() }` boilerplate is eliminated.

---

## Learning Hypothesis

We believe that `continueMaximally()` as a simple facade loop over `continue()` matches the output of the manual while-loop exactly, and that the concatenation strategy (join all return values) produces the expected output format. If the whitespace cleaning in `continue()` causes concatenation artefacts (e.g., double newlines between segments), this slice will surface that.

---

## Carpaccio Taste Test

- **Thin**: yes — pure facade delegation; zero engine or state changes; fewest lines of implementation in the feature
- **End-to-end**: yes — story author can write a complete 3-line GWT test using all four slices
- **Verifiable**: yes — `#expect(output.contains("gold badge."))` after `continueMaximally()` is directly observable
- **Stands alone**: yes — depends only on the already-existing `continue()` method; independent of Slices 01/02/03

---

## Public API Added

```swift
// Facade/Story.swift
@discardableResult
public func continueMaximally() -> String {
    var output = ""
    while canContinue {
        output += `continue`()
    }
    return output
}
```

The implementation is entirely within `Story.swift`. No changes to `InkEngine` or `StoryState`.

---

## Files Changed

- `Sources/SwiftInkRuntime/Facade/Story.swift` — add `continueMaximally()` (3-line implementation)

---

## Test Fixture

Reuse `slice-story-testability.ink.json` from Slices 01-03. No additional fixture content needed.

---

## Acceptance Criteria (Implementation Checklist)

- [ ] `story.continueMaximally()` returns the same string as a manual `while canContinue { output += continue() }` loop run on an identical story instance
- [ ] When `canContinue` is already `false`, returns `""`
- [ ] `@discardableResult` — return value can be ignored without a compiler warning
- [ ] Stops at choice point: when `canContinue` becomes false because choices are available, returns the text produced before the choice point
- [ ] Does not call `chooseChoice(at:)` — it only drains narrative output, never selects choices

---

## Swift Testing Examples (model for crafter)

```swift
@Test func `continueMaximally output equals manual while-loop output`() throws {
    let json = try loadTestabilityJSON()
    let storyA = try Story(json: json)
    let storyB = try Story(json: json)
    try storyA.moveToKnot("reward_check")
    try storyB.moveToKnot("reward_check")
    storyA.setVariable("score", to: 10)
    storyB.setVariable("score", to: 10)

    let outputA = storyA.continueMaximally()

    var outputB = ""
    while storyB.canContinue { outputB += storyB.`continue`() }

    #expect(outputA == outputB)
}

@Test func `continueMaximally on ended story returns empty string`() throws {
    let story = try makeTestabilityStory()
    while story.canContinue { _ = story.`continue`() }
    // Story has ended
    let output = story.continueMaximally()
    #expect(output == "")
    #expect(!story.canContinue)
}

@Test func `continueMaximally stops at choice point`() throws {
    let story = try makeTestabilityStory()
    // The story fixture has a choice point after the intro text
    let output = story.continueMaximally()
    #expect(!output.isEmpty)
    #expect(!story.currentChoices.isEmpty)
}
```

---

## Integration Checkpoints

- Verify that `continueMaximally()` does not loop infinitely if `canContinue` never becomes false (this would indicate a story bug, not a runtime bug; the method should not add timeout logic — that is the story author's problem)
- Verify that calling `continueMaximally()` on a fresh story (not yet positioned) does not crash
- Verify that the return value is the concatenation of individual `continue()` return values, not `currentText` (the distinction is important: `currentText` is the most recent line only)
- Confirm `@discardableResult` suppresses the "result of call unused" warning when the method is called purely for side effects (e.g., `story.continueMaximally()` to advance past preamble)

---

## Complete GWT Pattern After All Four Slices

After Slice 04 ships, a story author can write:

```swift
@Test func `score of 10 or more awards gold badge`() throws {
    // GIVEN
    let story = try Story(json: storyFixtureJSON)
    try story.moveToKnot("reward_check")
    story.setVariable("score", to: 10)

    // WHEN
    let output = story.continueMaximally()

    // THEN
    #expect(output.contains("You earned the gold badge."))
    #expect(story.getVariable("badge_awarded") as? Bool == true)
}
```

This is the target state. Every line of the test is direct, readable, and robust to story refactoring.
