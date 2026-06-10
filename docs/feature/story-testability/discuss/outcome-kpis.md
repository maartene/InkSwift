# Outcome KPIs: story-testability

## Feature: story-testability

### Objective

By end of 2026 Q2, Ink story authors using InkSwift can write GWT unit tests for individual story branches without replaying choice sequences — making story logic as testable as any other Swift code.

---

### Outcome KPIs

| # | Who | Does What | By How Much | Baseline | Measured By | Type |
|---|-----|-----------|-------------|----------|-------------|------|
| KPI-1 | Ink story authors using InkSwift | Write variable-assertion tests (`getVariable`/`setVariable`) without choice-replay setup | First project using the feature has ≥1 variable-assertion test per story knot with branching logic | 0 — no getVariable/setVariable on public API | Presence of `getVariable`/`setVariable` calls in story test files committed to version control | Leading |
| KPI-2 | Ink story authors using InkSwift | Write visit-count-injection tests without multi-playthrough setup | First project using the feature has ≥1 setVisitCount test for each visit-count-dependent knot | 0 — no visitCount/setVisitCount on public API | Presence of `setVisitCount` calls in story test files | Leading |
| KPI-3 | Ink story authors using InkSwift | Eliminate `while canContinue` boilerplate from test WHEN steps | 100% of new story tests use `continueMaximally()` instead of manual loops | 0 `continueMaximally` calls in codebase; manual while-loops in every Milestone test | Ratio of `continueMaximally` to `while.*canContinue` in test files | Leading |
| KPI-4 | Ink story test suites using InkSwift | Survive a story refactoring that changes choice ordering | Existing tests pass GREEN after a story edit that adds or reorders a choice — without test file changes | Tests that relied on `chooseChoice(at: N)` break on every story edit | Count of test failures caused by choice-index changes after adding the feature (target: 0 for tests using new API) | Leading |
| KPI-5 | InkSwift library (guardrail) | `getVariable`/`setVariable`/`visitCount`/`setVisitCount`/`continueMaximally` must not regress existing tests | 154/154 existing tests remain GREEN after each slice ships | 154 tests currently GREEN | CI green/red status after each slice merge | Guardrail |

---

### Metric Hierarchy

- **North Star**: Story authors can write a complete GWT test for any named knot in under 10 lines of Swift — without choice-replay setup.
- **Leading Indicators**:
  - `getVariable`/`setVariable` adoption in story test files (KPI-1)
  - `setVisitCount` adoption in story test files (KPI-2)
  - `continueMaximally` replaces manual loops (KPI-3)
  - Test refactoring survivability (KPI-4)
- **Guardrail Metrics**:
  - All 154 existing tests remain GREEN (KPI-5)
  - No `InkValue` type appears in the public API surface (enforced at compile time)
  - `StoryState` struct remains `internal` (enforced at compile time)

---

### Measurement Plan

| KPI | Data Source | Collection Method | Frequency | Owner |
|-----|------------|-------------------|-----------|-------|
| KPI-1 | Story test files in projects using InkSwift | `grep -r "getVariable\|setVariable" Tests/` | On adoption (manual) | Story author |
| KPI-2 | Story test files in projects using InkSwift | `grep -r "setVisitCount\|visitCount" Tests/` | On adoption (manual) | Story author |
| KPI-3 | InkSwift test suite + adopting projects | Ratio of `continueMaximally` to `while.*canContinue` | On each PR (manual review) | Maintainer |
| KPI-4 | CI pipeline | Green/red after story fixture edit + test run | Per story edit | Story author |
| KPI-5 | CI pipeline | `swift test` output — pass/fail count | Every commit | CI (automated) |

---

### Hypothesis

We believe that adding `getVariable`, `setVariable`, `visitCount`, `setVisitCount`, and `continueMaximally` to the `Story` public facade for Ink story authors will achieve test suites that survive story refactoring.

We will know this is true when story authors write ≥1 variable-assertion test per branching knot and those tests survive a choice-reordering refactoring without modification.

---

### Story-Level KPI Links

| User Story | KPI Link | Target |
|---|---|---|
| US-01 getVariable | KPI-1, KPI-5 | First variable-assertion test written using getVariable |
| US-02 setVariable | KPI-1, KPI-4, KPI-5 | Tests with setVariable survive choice-reordering |
| US-03 visitCount / setVisitCount | KPI-2, KPI-5 | First visit-count-injection test written |
| US-04 continueMaximally | KPI-3, KPI-5 | `while canContinue` boilerplate eliminated from new tests |
