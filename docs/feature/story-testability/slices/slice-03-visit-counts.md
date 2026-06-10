# Slice Brief: Slice 03 — visitCount / setVisitCount

**Feature**: story-testability  
**Slice**: 03  
**Estimated effort**: 0.5 days  
**User story**: US-03  
**Date**: 2026-06-10  
**Depends on**: None (independent of Slices 01/02)

---

## Slice Goal

Add `public func visitCount(forKnot name: String) -> Int` and `public func setVisitCount(forKnot name: String, to count: Int)` to `Story`.

After this slice, a story author can test stories that use Ink's built-in `{knotName}` visit count syntax without replaying the story multiple times.

---

## Learning Hypothesis

We believe that `visitCounts[knotName]` is the correct read/write key for named knots (matching what inklecate writes during natural execution). If the actual key format differs from the knot name string (e.g., includes a path prefix), this slice will surface that as a RED test, and the DESIGN wave will address the key lookup mechanism.

---

## Carpaccio Taste Test

- **Thin**: yes — two symmetric methods on a single dict (`visitCounts`); completely independent of `variablesState`
- **End-to-end**: yes — story author can inject a visit count and verify a visit-count-dependent branch
- **Verifiable**: yes — `#expect(story.visitCount(forKnot: "prologue") == 3)` is directly observable
- **Stands alone**: yes — independent of Slices 01, 02, and 04

---

## Public API Added

```swift
// Facade/Story.swift
public func visitCount(forKnot name: String) -> Int
public func setVisitCount(forKnot name: String, to count: Int)
```

**Behaviour**:

| Scenario | visitCount behaviour | setVisitCount behaviour |
|---|---|---|
| Known named knot | Returns `visitCounts[name] ?? 0` | Writes `visitCounts[name] = count` |
| Unknown name | Returns `0` | No-op (do not create key) |
| Anonymous container path | Not exposed — story authors have no way to obtain these keys |

---

## Files Changed

- `Sources/SwiftInkRuntime/Facade/Story.swift` — add `visitCount(forKnot:)` and `setVisitCount(forKnot:to:)` delegating to InkEngine
- `Sources/SwiftInkRuntime/Engine/InkEngine.swift` — add internal accessors for `visitCounts`

---

## Test Fixture Needed

Extend `slice-story-testability.ink.json` (from Slice 01) with a knot that uses `{knotName}` visit count syntax:

```ink
=== greeting ===
{ prologue > 1:
    Welcome back! You have visited prologue {prologue} times.
- else:
    Welcome, first-time visitor.
}
-> DONE

=== prologue ===
Once upon a time.
-> DONE
```

---

## Acceptance Criteria (Implementation Checklist)

- [ ] `story.visitCount(forKnot: "prologue")` returns `0` before any navigation
- [ ] `story.setVisitCount(forKnot: "prologue", to: 2)` writes the count; `story.visitCount(forKnot: "prologue")` returns `2`
- [ ] Setting visit count to 2 for "prologue" causes `continueMaximally()` from "greeting" to produce "Welcome back!"
- [ ] `story.visitCount(forKnot: "nonexistent")` returns `0` without throwing
- [ ] `story.setVisitCount(forKnot: "nonexistent", to: 5)` does not throw
- [ ] Natural navigation: after `story.moveToKnot("prologue")` + `story.continue()`, `story.visitCount(forKnot: "prologue")` returns 1 (or more, depending on engine increment timing)

---

## Swift Testing Examples (model for crafter)

```swift
@Test func `setVisitCount enables visit-count-dependent branch`() throws {
    let story = try makeTestabilityStory()
    story.setVisitCount(forKnot: "prologue", to: 2)
    try story.moveToKnot("greeting")
    var output = ""
    while story.canContinue { output += story.`continue`() }
    #expect(output.contains("Welcome back!"))
}

@Test func `visitCount read-back matches what was set`() throws {
    let story = try makeTestabilityStory()
    story.setVisitCount(forKnot: "prologue", to: 3)
    #expect(story.visitCount(forKnot: "prologue") == 3)
}

@Test func `visitCount for unknown knot returns zero`() throws {
    let story = try makeTestabilityStory()
    #expect(story.visitCount(forKnot: "chapter_four") == 0)
}
```

---

## Integration Checkpoints

- Verify the key format used by inklecate for named knots in `visitCounts` — must match before writing the implementation (inspect `slice-story-testability.ink.json` compiled output)
- Verify that `setVisitCount` values survive a `moveToKnot` call (visit counts are preserved across jumps per architecture brief D1)
- Verify that `visitCounts` starts as an empty dict for a freshly loaded story with no navigation (no crash on first call)
- Confirm that anonymous container keys (e.g., `"prologue.1.g-0"`) are NOT returned or accepted — the API silently ignores them (they are not named knots)
