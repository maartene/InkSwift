<!-- markdownlint-disable MD024 -->
# User Stories: story-testability

## System Constraints

- `InkValue` (internal enum) MUST NOT appear in the public API — bridge to Swift native types (`Int`, `Double`, `String`, `Bool`, `Any?`)
- `StoryState` struct stays `internal` — public API exposes named methods on `Story` only
- `InkSwift` module (JS bridge) is frozen — no changes permitted there
- All test examples in this document use Swift Testing backtick function-name style (CLAUDE.md mandate)
- Visit count API is for **named knots only** — anonymous container paths are not exposed
- `moveToKnot` already exists — these features complement it; they do not replace it

---

## US-01: Read a Story Variable

### Elevator Pitch

**Before**: Raya has no way to read a VAR value from a running story without internal access to `StoryState.variablesState`. She must infer state from output text, which is fragile.  
**After**: Raya calls `story.getVariable("score")` on the `Story` public facade and receives the current value as a Swift-native type (`Int`, `Bool`, etc.) or `nil` if the variable does not exist.  
**Decision enabled**: Raya can write THEN assertions that verify variable post-conditions — not just output text — confirming that story logic updated the right variables after execution.

### Problem

Raya is a Swift developer who writes Ink stories and wants to verify story logic with automated tests. She finds it frustrating to infer story variable state from output text alone. When a story sets `score += 10`, she wants to assert `#expect(story.getVariable("score") as? Int == 10)` directly — not scan output strings for numeric clues.

### Who

- Swift developer / Ink story author | Writing Swift Testing suites for an Ink story | Wants direct variable read access without internal module hacks

### Solution

Add `public func getVariable(_ name: String) -> Any?` to `Story`. The method reads from `engine.state.variablesState[name]` and bridges `InkValue` to a Swift native type (`Int`, `Double`, `String`, `Bool`). Returns `nil` for unknown names or `variablePointer` cases.

### Domain Examples

#### 1: Happy Path — Read an integer variable after execution
Raya's story has `VAR score = 0`. After calling `story.continue()` through a knot that runs `~ score = 42`, she calls `story.getVariable("score")` and receives `42` as an `Any?` that casts cleanly to `Int`.

#### 2: Boolean variable — Read a flag set by story logic
Raya's story has `VAR badge_awarded = false`. After `continueMaximally()` through the reward knot, `story.getVariable("badge_awarded")` returns `true` (bridged from `InkValue.bool(true)`).

#### 3: Unknown variable — No variable named "ghost_var" exists
Raya mistypes a variable name. `story.getVariable("ghost_var")` returns `nil`. The test reads `#expect(story.getVariable("ghost_var") == nil)` which passes, or the `as? Int` cast returns `nil`, which #expect treats as a failure with a clear message.

### UAT Scenarios (BDD)

#### Scenario: Integer variable value is readable after execution
```
Given Raya has a Story where VAR score starts at 0
And the story has been positioned at a knot that sets score to 42
When Raya calls story.continueMaximally()
And Raya calls story.getVariable("score")
Then the returned value casts to Int as 42
```

#### Scenario: Boolean variable value is readable after execution
```
Given Raya has a Story where VAR badge_awarded starts as false
And the story logic sets badge_awarded to true during execution
When Raya calls story.continueMaximally()
And Raya calls story.getVariable("badge_awarded")
Then the returned value casts to Bool as true
```

#### Scenario: Reading an unknown variable returns nil
```
Given a Story is loaded
When Raya calls story.getVariable("nonexistent_variable")
Then the return value is nil
And no error is thrown
```

#### Scenario: String variable value is readable
```
Given Raya has a Story where VAR player_name = "unnamed"
And the story sets player_name to "Raya" during execution
When Raya calls story.getVariable("player_name")
Then the returned value casts to String as "Raya"
```

### Acceptance Criteria

- [ ] `story.getVariable("score")` returns the current value of a declared VAR as `Any?`
- [ ] Return type bridges correctly: `InkValue.int` → `Int`, `InkValue.float` → `Double`, `InkValue.string` → `String`, `InkValue.bool` → `Bool`
- [ ] `story.getVariable("nonexistent")` returns `nil` without throwing
- [ ] `InkValue.variablePointer` cases return `nil` (not a user-accessible value)
- [ ] Method signature: `public func getVariable(_ name: String) -> Any?`

### Outcome KPIs

- **Who**: Ink story authors using InkSwift
- **Does what**: Write THEN assertions on variable post-conditions
- **By how much**: At least 1 variable assertion per story test where previously 0 were possible
- **Measured by**: Presence of `getVariable` calls in story test files
- **Baseline**: 0 — no getVariable method exists on the public API

### Technical Notes

- Reads from `engine.state.variablesState[name]`; delegates through InkEngine internal accessor
- `InkValue` must not appear in method signature (constraint)
- `variablePointer` case is internal (ref param mechanism) — return `nil` for this case
- No new StoryState fields needed — read-only access to existing dict

---

## US-02: Write a Story Variable

### Elevator Pitch

**Before**: Raya must replay a fragile chain of `chooseChoice(at:)` calls to reach a story state where a variable has a specific value. When story authors add a choice, all test indices break.  
**After**: Raya calls `story.setVariable("score", to: 10)` on the `Story` public facade to inject GIVEN preconditions directly — no choice-replay chain needed.  
**Decision enabled**: Raya can rewrite fragile choice-sequence setup as direct state injection, making tests resilient to story refactoring.

### Problem

Raya is a Swift developer who writes Ink stories and wants to verify story logic with automated tests. She finds it frustrating that setting up a test precondition requires replaying a fragile choice sequence. When `chooseChoice(at: 2)` becomes `chooseChoice(at: 3)` after a story edit, every test depending on that path breaks silently. She wants to write `story.setVariable("hasKey", to: true)` and have the variable set directly.

### Who

- Swift developer / Ink story author | Writing unit tests for story conditional logic | Wants to inject preconditions without replay

### Solution

Add `public func setVariable(_ name: String, to value: some Any)` to `Story`. The method writes into `engine.state.variablesState[name]`, bridging Swift native types to `InkValue`. Unknown variable names are a silent no-op (no throw). This is also needed in production code (e.g., host app setting player name before story starts).

### Domain Examples

#### 1: Happy Path — Set an integer variable as a test precondition
Raya's story has `VAR score = 0`. She calls `story.setVariable("score", to: 10)` and then `continueMaximally()`. The output contains `"You earned the gold badge."` because the story's conditional checks `score >= 10`.

#### 2: Boolean flag injection — Skip a prerequisite path
Raya's story has `VAR has_key = false`. Rather than navigating through the `find_key` knot, she calls `story.setVariable("has_key", to: true)` and jumps directly to `locked_door` to test the "door opens" path in isolation.

#### 3: Unknown variable — Silent no-op
Raya mistypes `story.setVariable("scroe", to: 10)`. No error is thrown. `story.getVariable("score")` still returns the prior value. The variable `"scroe"` does not appear in `variablesState` after the call (or is written as a new key depending on implementation choice — see technical notes).

### UAT Scenarios (BDD)

#### Scenario: Setting a variable changes subsequent story output
```
Given Raya has a Story positioned at the "reward_check" knot
And VAR score is 0
When Raya calls story.setVariable("score", to: 10)
And Raya calls story.continueMaximally()
Then the output contains "You earned the gold badge."
```

#### Scenario: Variable read-back confirms the value was set
```
Given Raya has a Story instance
When Raya calls story.setVariable("score", to: 42)
Then story.getVariable("score") as? Int equals 42
```

#### Scenario: Setting an unknown variable does not throw
```
Given a Story is loaded
When Raya calls story.setVariable("nonexistent_variable", to: 99)
Then no error is thrown
And story.getVariable("nonexistent_variable") returns nil or 99 (implementation decision: see technical notes)
```

#### Scenario: Boolean value injection enables a conditional branch
```
Given Raya has a Story with VAR has_key = false at knot "locked_door"
When Raya calls story.setVariable("has_key", to: true)
And Raya calls story.continueMaximally()
Then the output contains "The door swings open."
And the output does not contain "You need a key."
```

#### Scenario: String value injection personalises output
```
Given Raya has a Story with VAR player_name = "unnamed"
When Raya calls story.setVariable("player_name", to: "Raya")
And Raya calls story.continueMaximally()
Then the output contains "Raya"
```

### Acceptance Criteria

- [ ] `story.setVariable("score", to: 42)` writes the value into story state; subsequent `getVariable("score")` returns `42`
- [ ] Supported types: `Int`, `Double`, `String`, `Bool` (bridged to `InkValue`)
- [ ] Setting an unknown variable name does not throw
- [ ] Setting a variable does not affect `canContinue`, `currentChoices`, or execution position
- [ ] Method signature: `public func setVariable(_ name: String, to value: some Any)`

### Outcome KPIs

- **Who**: Ink story authors using InkSwift
- **Does what**: Inject GIVEN preconditions via setVariable instead of choice-replay chains
- **By how much**: Test setup lines reduced from N choice-replay steps to 1 setVariable call per variable
- **Measured by**: Ratio of setVariable calls to chooseChoice calls in story test files (leading indicator)
- **Baseline**: 0 setVariable calls; all precondition setup via chooseChoice

### Technical Notes

- Writes to `engine.state.variablesState[name]`; must bridge Swift types to InkValue
- Unknown variable name: preferred behaviour is no-op (do not create new keys for typos); discussion point for DESIGN wave
- `some Any` or overloaded methods per type (`to value: Int`, `to value: Bool`, etc.) — signature choice deferred to DESIGN wave
- Also needed in production code (host app initialising player data before story starts)
- Does not clear or reset execution position — does not call moveToKnot internally

---

## US-03: Read and Write Knot Visit Counts

### Elevator Pitch

**Before**: Raya cannot test stories that use Ink's built-in `{knotName}` visit count syntax (`Pattern B`) because there is no API to read or inject `visitCounts` from outside the internal engine state.  
**After**: Raya calls `story.visitCount(forKnot: "prologue")` to read a count and `story.setVisitCount(forKnot: "prologue", to: 2)` to inject one on the `Story` public facade.  
**Decision enabled**: Raya can test visit-count-dependent story branches (e.g., "if the player has visited prologue twice, show the recall dialogue") without replaying the story multiple times.

### Problem

Raya is a Swift developer who writes Ink stories and wants to verify story logic. She finds it frustrating that stories using Ink's `{knotName}` visit count operator cannot be unit-tested with injected state. Her story has logic like `{ prologue > 1: Welcome back. }` and she wants to write a test that sets the prologue visit count to 2 and verifies the recall text appears — without actually visiting prologue twice.

### Who

- Swift developer / Ink story author | Testing visit-count-dependent story logic | Uses both Pattern A (VAR) and Pattern B ({knotName}) in the same story

### Solution

Add `public func visitCount(forKnot name: String) -> Int` and `public func setVisitCount(forKnot name: String, to count: Int)` to `Story`. Both read/write `engine.state.visitCounts[name]`. Unknown knot name returns `0` for read and is a silent no-op for write. Named knots only — anonymous container paths are not exposed.

### Domain Examples

#### 1: Happy Path — Inject a visit count to trigger recall dialogue
Raya's story has `{ prologue > 1: Welcome back! }`. She calls `story.setVisitCount(forKnot: "prologue", to: 2)` and then `continueMaximally()`. The output contains `"Welcome back!"` because the visit count condition is satisfied.

#### 2: Read-back — Verify visit count after natural navigation
Raya positions the story at the `prologue` knot and calls `continue()`. She then reads `story.visitCount(forKnot: "prologue")` and expects `1`. This confirms the engine increments visit counts correctly on knot entry.

#### 3: Unknown knot — Returns zero, does not throw
Raya calls `story.visitCount(forKnot: "chapter_four")` when `chapter_four` does not exist in the loaded story. The return value is `0`. No exception is raised.

### UAT Scenarios (BDD)

#### Scenario: Setting a visit count enables a visit-count-dependent branch
```
Given Raya has a Story with logic "{ prologue > 1: Welcome back! }" at knot "greeting"
And prologue visit count is currently 0
When Raya calls story.setVisitCount(forKnot: "prologue", to: 2)
And Raya calls story.moveToKnot("greeting")
And Raya calls story.continueMaximally()
Then the output contains "Welcome back!"
```

#### Scenario: Visit count read-back matches what was set
```
Given a Story is loaded
When Raya calls story.setVisitCount(forKnot: "prologue", to: 3)
Then story.visitCount(forKnot: "prologue") returns 3
```

#### Scenario: Reading visit count for unknown knot returns zero
```
Given a Story is loaded
When Raya calls story.visitCount(forKnot: "nonexistent_knot")
Then the return value is 0
And no error is thrown
```

#### Scenario: Natural story execution increments visit count
```
Given a Story is loaded and positioned at knot "prologue"
When Raya calls story.continue()
Then story.visitCount(forKnot: "prologue") returns 1 (or more if the knot auto-increments on entry)
```

### Acceptance Criteria

- [ ] `story.visitCount(forKnot: "prologue")` returns the current visit count as `Int`
- [ ] `story.setVisitCount(forKnot: "prologue", to: 2)` writes the count; subsequent `visitCount(forKnot: "prologue")` returns `2`
- [ ] Unknown knot name: `visitCount` returns `0`; `setVisitCount` is a silent no-op (no throw)
- [ ] Anonymous container paths are not exposed — only named knot strings are valid
- [ ] Method signatures: `public func visitCount(forKnot name: String) -> Int` and `public func setVisitCount(forKnot name: String, to count: Int)`

### Outcome KPIs

- **Who**: Ink story authors using visit-count-dependent story logic
- **Does what**: Write unit tests for `{knotName}` conditional branches without replaying navigation paths
- **By how much**: Visit-count-dependent branches become testable with injected state (currently 0% testable without full playthrough)
- **Measured by**: Presence of `setVisitCount` calls in story test files
- **Baseline**: 0 — no visitCount or setVisitCount method exists on the public API

### Technical Notes

- Reads/writes `engine.state.visitCounts[name]` — a `[String: Int]` dict, currently internal
- The key format for named knots is the knot name string directly (matching inklecate-compiled keys)
- Anonymous container paths (choice arm paths, gather paths) have opaque keys — do NOT expose these
- `setVisitCount` is symmetric with `setVariable`: unknown name is a no-op, no throw
- This is the only slice that touches `visitCounts` — no dependency on US-01 or US-02

---

## US-04: Drain All Story Output with continueMaximally

### Elevator Pitch

**Before**: Raya must write a manual `while story.canContinue { output += story.continue() }` loop in every test to collect all output from a knot. This is four lines of boilerplate repeated in every WHEN step.  
**After**: Raya calls `story.continueMaximally()` on the `Story` public facade and receives the full concatenated output from the current position to the next choice point (or story end) in one line.  
**Decision enabled**: Raya can write the WHEN step in a single line that matches the reference inkjs/C# API — making InkSwift story tests readable and consistent with the broader Ink ecosystem.

### Problem

Raya is a Swift developer who writes Ink stories and wants to verify story logic. She finds it frustrating to write the same `while canContinue { output += continue() }` boilerplate in every test. When the reference C# Ink API has `ContinueMaximally()`, InkSwift should match it. The manual loop also invites subtle bugs (e.g., off-by-one on the final line, forgetting to initialise `output`).

### Who

- Swift developer / Ink story author | Writing the WHEN step of a GWT story test | Wants concise, readable test code matching the reference API

### Solution

Add `@discardableResult public func continueMaximally() -> String` to `Story`. The method loops `continue()` until `canContinue == false`, concatenates all returned strings, and returns the result. If `canContinue` is already false, returns `""`. This is also needed in production code (e.g., headless story execution for server-side rendering).

### Domain Examples

#### 1: Happy Path — Collect all output from a positioned knot
Raya positions at `"reward_check"`, sets `score` to 10, calls `story.continueMaximally()`. The return value is `"You walk up to the podium.\nThe judge nods.\nYou earned the gold badge.\n"`. She asserts `output.contains("gold badge")`.

#### 2: Multi-line output with embedded newlines
A knot produces three separate `continue()` calls (three output segments). `continueMaximally()` returns them joined. The concatenation matches `line1 + line2 + line3` exactly.

#### 3: Already-ended story — Returns empty string immediately
Raya's story has reached its `END`. She calls `story.continueMaximally()`. The return value is `""`. `canContinue` remains `false`. No error is thrown.

### UAT Scenarios (BDD)

#### Scenario: All output lines from a knot are collected in one call
```
Given Raya has a Story positioned at knot "reward_check" with score set to 10
When Raya calls story.continueMaximally()
Then the return value contains "You earned the gold badge."
And story.canContinue is false (or story is at a choice point)
```

#### Scenario: continueMaximally output equals manual while-loop output
```
Given two Story instances loaded from the same JSON, both positioned at the same knot
When instance A runs the manual while-loop: while canContinue { output += continue() }
And instance B calls continueMaximally()
Then instance A's output equals instance B's output
```

#### Scenario: continueMaximally on an already-ended story returns empty string
```
Given a Story instance where canContinue is false (story has ended)
When Raya calls story.continueMaximally()
Then the return value is ""
And no error is thrown
And canContinue remains false
```

#### Scenario: continueMaximally stops at a choice point
```
Given a Story positioned at a knot that produces text then presents choices
When Raya calls story.continueMaximally()
Then the return value contains the text produced before the choices
And story.currentChoices is non-empty
```

### Acceptance Criteria

- [ ] `story.continueMaximally()` returns the concatenation of all `continue()` calls until `canContinue == false`
- [ ] Result is identical to manual `while canContinue { output += continue() }` loop
- [ ] When `canContinue` is already false, returns `""`
- [ ] `@discardableResult` — return value may be ignored (matches production headless use case)
- [ ] Stops at a choice point: if `canContinue` becomes false because choices are available, returns the text output before the choice point
- [ ] Method signature: `@discardableResult public func continueMaximally() -> String`

### Outcome KPIs

- **Who**: Ink story authors using InkSwift
- **Does what**: Write the WHEN step as a single line instead of a while-loop
- **By how much**: WHEN step reduced from 3–4 lines of boilerplate to 1 line in every test
- **Measured by**: Presence of `continueMaximally` calls in story test files; absence of `while canContinue` boilerplate in new tests
- **Baseline**: 0 — no continueMaximally method exists; every test uses a manual loop

### Technical Notes

- Implementation is in `Story` facade only: loop `engine.step()` + `cleanOutputWhitespace` via the existing `continue()` method
- No new engine or state changes needed — pure delegation
- The `cleanOutputWhitespace` logic in `continue()` already handles individual line whitespace; concatenation preserves newlines
- In production headless rendering (server-side), also needed: do not restrict to tests only
