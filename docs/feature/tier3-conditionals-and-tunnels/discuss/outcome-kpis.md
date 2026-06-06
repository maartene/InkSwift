# Outcome KPIs — tier3-conditionals-and-tunnels

## Feature: tier3-conditionals-and-tunnels

### Objective
By the end of Tier 3, `SwiftInkRuntime` can execute The Intercept (inkle, MIT) end-to-end with output matching the JS-bridge oracle — proving that the native Swift engine is a viable replacement for the 246 KB JS dependency for any story up to The Intercept's complexity.

---

### Outcome KPIs

| # | Who | Does What | By How Much | Baseline | Measured By | Type |
|---|-----|-----------|-------------|----------|-------------|------|
| 1 | Swift developer using SwiftInkRuntime | Runs stories with inline conditional text without oracle mismatch | 100% of `{c: a\|b}` lines match oracle | 0% correct (not wired) | Oracle comparison test (XCTAssertEqual per line) | Leading |
| 2 | Swift developer using SwiftInkRuntime | Runs stories with block/switch conditionals without oracle mismatch | 100% of block conditional branches match oracle | 0% correct (not wired) | Oracle comparison test | Leading |
| 3 | Swift developer using SwiftInkRuntime | Uses Ink functions that produce correct return values in output | 100% of function call output lines match oracle; 0 `"void"` literals in output | 0% correct (not wired) | Oracle comparison test + explicit `"void"` absence assertion | Leading |
| 4 | Swift developer using SwiftInkRuntime | Runs stories with tunnels that complete and return to the correct caller | 100% of tunnel call/return pairs produce correct post-tunnel text | 0% correct (not wired; story stalls) | Oracle comparison test + `canContinue` assertion at each post-tunnel step | Leading |
| 5 | Swift developer using SwiftInkRuntime | Uses `ref` parameters that mutate caller-side variables correctly | 100% of `ref` parameter mutations match oracle variable values | 0% correct (not wired; caller variable unchanged) | Oracle comparison test + variable value assertions | Leading |
| 6 | Swift developer maintaining the test suite | Sees zero regressions in Tier 1 and Tier 2 tests after each Tier 3 slice | 0 regressions (all pre-existing tests remain green) | All existing tests green | `swift test` exit code and test report | Guardrail |

---

### Metric Hierarchy

- **North Star**: The Intercept plays end-to-end via `SwiftInkRuntime` with output matching `InkSwift` (JS bridge) for every line and choice — demonstrating the engine reaches The Intercept ceiling.
- **Leading Indicators**:
  - Inline conditional text oracle-match rate (KPI 1)
  - Block/switch conditional oracle-match rate (KPI 2)
  - Function return value oracle-match rate (KPI 3)
  - Tunnel continuation oracle-match rate (KPI 4)
  - Ref parameter mutation oracle-match rate (KPI 5)
- **Guardrail Metrics**:
  - Tier 1 + Tier 2 regression count = 0 (KPI 6)
  - `"void"` literal occurrence in output = 0 (embedded in KPI 3)
  - `returnStack` unbalanced entries after story completes = 0 (embedded in KPI 4)

---

### Measurement Plan

| KPI | Data Source | Collection Method | Frequency | Owner |
|-----|------------|-------------------|-----------|-------|
| KPI 1 — Inline conditional | SwiftInkRuntimeTests/Integration/ConditionalTextTests | XCTAssertEqual per continue() line vs oracle | Per-slice CI run | Developer |
| KPI 2 — Block/switch conditional | SwiftInkRuntimeTests/Integration/ConditionalTextTests | XCTAssertEqual per continue() line vs oracle | Per-slice CI run | Developer |
| KPI 3 — Functions | SwiftInkRuntimeTests/Integration/FunctionTests | XCTAssertEqual + void-absence assertion | Per-slice CI run | Developer |
| KPI 4 — Tunnels | SwiftInkRuntimeTests/Integration/TunnelTests | XCTAssertEqual + canContinue + returnStack count | Per-slice CI run | Developer |
| KPI 5 — Ref params | SwiftInkRuntimeTests/Integration/TunnelTests | XCTAssertEqual + variable value assertions | Per-slice CI run | Developer |
| KPI 6 — No regression | Full test suite (`swift test`) | Exit code = 0; zero red tests | After every merge | CI |

---

### Hypothesis

We believe that extending `TreeWalker`, `InkEngine`, and `InkDecoder` to handle conditional text nodes, function call/return frames, and tunnel call/return frames for Swift game developers will achieve native execution of The Intercept end-to-end.

We will know this is true when a Swift developer can call `Story.continue()` and `Story.chooseChoice(at:)` through The Intercept's full story tree and every output line matches `InkStory.continue()` from the JS-bridge oracle, with zero `"void"` literals, zero premature endings, and zero Tier 1–2 regressions.
