# Outcome KPIs — native-move-to-knot

Feature ID: native-move-to-knot
Date: 2026-06-08

---

## Feature: native-move-to-knot

### Objective
Deliver a safe, reliable `moveToKnot` API for `SwiftInkRuntime` that lets Swift developers redirect a running story to any named knot or stitch — with the same behavioural guarantee as the JS-bridge reference — by end of the current sprint (2026-06-08).

---

### Outcome KPIs

| # | Who | Does What | By How Much | Baseline | Measured By | Type |
|---|-----|-----------|-------------|----------|-------------|------|
| 1 | Swift developer using SwiftInkRuntime | Redirects a running story to a named knot without reloading the story JSON | 100% of moveToKnot calls to existing knots succeed; post-jump continue() output matches oracle (0 mismatches) | Feature does not exist; 0% success rate | Oracle comparison test: XCTAssertEqual on every post-jump continue() line | Leading |
| 2 | Swift developer using SwiftInkRuntime | Catches and handles an invalid-knot error without crashing | 100% of calls with non-existent knot names throw StoryError.knotNotFound (0 silent failures) | Feature does not exist; invalid targets either crash or are silently ignored | XCTAssertThrowsError on all invalid-path test cases | Leading |
| 3 | Swift developer using SwiftInkRuntime | Auto-saves after a chapter jump and resumes correctly on restore | 100% of save/restore round-trips after a jump resume from the correct post-jump location (0 location corruptions) | Undefined (no jump feature exists) | Assertion: freshStory.continue() == in-memory story.continue() at each step | Leading |

---

### Metric Hierarchy

- **North Star**: `moveToKnot` output matches JS-bridge oracle for all jump scenarios (KPI #1)
- **Leading Indicators**:
  - `StoryError.knotNotFound` is thrown for all invalid paths (KPI #2)
  - Save/restore round-trip after jump is correct (KPI #3)
- **Guardrail Metrics**:
  - Existing test suite (154 tests) stays GREEN — no regressions
  - `StoryState` serialisation format is unchanged (no new fields)

---

### Measurement Plan

| KPI | Data Source | Collection Method | Frequency | Owner |
|-----|------------|-------------------|-----------|-------|
| #1 Oracle match | `SwiftInkRuntimeTests` integration tests | XCTAssertEqual post-jump continue() vs InkStory oracle | Every CI run | Solution architect (DESIGN wave) |
| #2 Error throwing | `SwiftInkRuntimeTests` unit tests | XCTAssertThrowsError on invalid-path calls | Every CI run | Solution architect |
| #3 Save/restore | `SwiftInkRuntimeTests` integration tests | Explicit assertion: freshStory line-by-line match | Every CI run | Solution architect |
| Guardrail: no regressions | Full test suite | `swift test` exit code | Every CI run | CI gate |

---

### Hypothesis

We believe that adding `moveToKnot(_:stitch:)` to `Story` in `SwiftInkRuntime` for Swift developers building narrative games will allow them to implement chapter-select and scene-replay features without reloading the story JSON.

We will know this is true when Swift developers can call `story.moveToKnot("knot")`, then `story.continue()`, and receive the correct knot content in 100% of cases — matching the JS-bridge oracle — with zero regressions in the existing 154-test suite.
