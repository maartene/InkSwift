<!-- markdownlint-disable MD024 -->
# User Stories — tier3-conditionals-and-tunnels

Feature type: Backend (engine mechanics)
Feature ID: tier3-conditionals-and-tunnels

## System Constraints

The following constraints apply to every story in this feature:

1. **Save/restore invariant** — every behaviour must survive a `saveState()` → `restoreState()` round-trip into a fresh `Story` instance. Any new `StoryState` field uses `decodeIfPresent` with a safe default.
2. **Inklecate fixtures only** — test fixtures must be compiled from real Ink source using inklecate at `/Users/maartene/Downloads/inklecate_mac/inklecate`. No hand-crafted JSON.
3. **Zero regressions** — all existing Tier 1 and Tier 2 tests must remain green after each slice ships.
4. **No new runtime dependencies** — `SwiftInkRuntime` must remain dependency-free (Foundation only).
5. **macOS-arm64 only** — Linux CI deferred; test target is macOS-arm64.
6. **Swift Testing style** — all tests use backtick function-name style; string-label form is forbidden.

---

## Story C1 — Inline Conditional Text Evaluates Correctly

### Problem
Ava is a Swift game developer using `SwiftInkRuntime` to run an Ink story for her narrative game. She finds it impossible to run stories that use `{condition: true-text|false-text}` inline alternation — the engine ignores the condition and outputs the wrong branch (or nothing at all), making every story with personalised or reactive text broken.

### Who
- Ava — Swift developer building a narrative game
- Authoring an Ink story with inline conditionals like `{metCass: You know her.|She's a stranger.}`
- Motivated to ship a native Swift engine that handles the most common Ink idiom

### Solution
Extend `TreeWalker` (and if needed `InkDecoder`) to evaluate the inline conditional node: pop the condition value from `evalStack`, select the correct branch container, and push only that branch's content to the output stream.

### Elevator Pitch
Before: `{metCass: You know her.|She's a stranger.}` always outputs the wrong branch or nothing — the condition is ignored entirely.
After: set `metCass` to true → `story.continue()` returns `"You know her."`. Set it to false → returns `"She's a stranger."`.
Decision enabled: Ava can ship a story with personalised text without workarounds in the host app.

### Domain Examples

#### 1: Variable-based true branch (happy path)
Story `conditional_inline.ink` compiled to JSON. Variable `metCass` is true. Story advances to the inline conditional line. `story.continue()` returns `"You know her."`. The false branch text `"She's a stranger."` does not appear.

#### 2: Variable-based false branch
Same fixture. Variable `metCass` is false. `story.continue()` returns `"She's a stranger."`. True branch text is absent.

#### 3: Save/restore preserves branch selection
Variable `metCass` is true. Story advances to just before the conditional. Ava calls `story.saveState()`. A fresh `Story` instance is created and `story.restoreState(savedData)` is called. The restored story calls `story.continue()` and returns `"You know her."` — identical to the in-memory run.

### UAT Scenarios (BDD)

#### Scenario: True-branch text appears when condition is true
Given Ava has loaded a story containing `{metCass: You know her.|She's a stranger.}`
And the story variable `metCass` is set to true
When Ava calls `story.continue()`
Then `story.currentText` contains `"You know her."`
And `story.currentText` does not contain `"She's a stranger."`

#### Scenario: False-branch text appears when condition is false
Given Ava has loaded a story containing `{metCass: You know her.|She's a stranger.}`
And the story variable `metCass` is set to false
When Ava calls `story.continue()`
Then `story.currentText` contains `"She's a stranger."`
And `story.currentText` does not contain `"You know her."`

#### Scenario: Inline conditional output matches JS-bridge oracle
Given both `Story` (native) and `InkStory` (oracle) are loaded from the same inklecate-compiled fixture
And the same variable state is set on both
When both are driven forward with `continue()`
Then the output from `Story.currentText` equals the output from `InkStory.currentText`

#### Scenario: Condition re-evaluation after variable change
Given Ava has a story with `{score > 5: You passed.|You failed.}`
And `score` is initially 3 (condition false → "You failed.")
When Ava sets `score` to 7 and replays the conditional
Then `story.currentText` contains `"You passed."`

#### Scenario: Save/restore preserves correct branch
Given the condition evaluates to the true branch in memory
When Ava saves and restores into a fresh Story instance
Then the restored story produces the same true-branch text on `continue()`

### Acceptance Criteria
- [ ] True-branch text is output when the condition evaluates to true
- [ ] False-branch text is output when the condition evaluates to false
- [ ] No branch text from the non-selected path appears in output
- [ ] Native runtime output matches JS-bridge oracle for all inline conditional scenarios
- [ ] Save/restore round-trip produces identical branch selection

### Outcome KPIs
- **Who**: Swift developer using SwiftInkRuntime
- **Does what**: Runs a story with inline conditional text without patching the host app
- **By how much**: 100% of `{c: a|b}` conditionals in the test fixture produce correct output (0 mismatches vs oracle)
- **Measured by**: Oracle comparison test — XCTAssertEqual on every continue() line
- **Baseline**: 0% correct (feature not wired; wrong/empty output always)

### Technical Notes
- Inline conditionals in inklecate JSON are likely encoded as a container with an `ev`/`/ev` block pushing the condition, followed by two child containers for the branches — verify exact encoding by inspecting a compiled fixture before implementing.
- The condition evaluation re-uses the existing `evalStack` machinery from Tier 2 conditional choices.
- Dependencies: none within Tier 3 (independent of C2, C3, T1–T3).
- Brief coverage: row 22 of the Feature Coverage Matrix.

---

## Story C2 — Block and Switch Conditionals Evaluate Correctly

### Problem
Ava is writing an Ink story that uses multi-branch block conditionals (`{c: ... - else: ...}`) and switch-style dispatch (`{v: - 1: ... - 2: ...}`). The engine does not handle these forms — it either outputs nothing, outputs all branches, or crashes — making any story that uses Ink's standard if/else or CONST dispatch patterns unplayable.

### Who
- Ava — Swift developer building a narrative game
- Authoring an Ink story using block conditionals for narrative branching and CONST-based dispatch
- Motivated by The Intercept's heavy use of both forms

### Solution
Extend the tree-walker to handle the block conditional and switch-style conditional node forms emitted by inklecate, correctly selecting the matching branch and suppressing the others.

### Elevator Pitch
Before: `{ score > 10:\n    You passed.\n- else:\n    You failed. }` either outputs both branches or neither — the conditional jump is not recognised.
After: `story.continue()` returns `"You passed."` when `score` is 11 and `"You failed."` when it is 5. No extra text.
Decision enabled: Ava can write stories with multi-branch logic and trust the engine to route correctly.

### Domain Examples

#### 1: If/else block — condition true
Fixture `block_conditional.ink` compiled. `score` = 11. The `{score > 10: You passed. - else: You failed.}` block outputs `"You passed."`. The else text is absent.

#### 2: Switch-style dispatch — matching case
Fixture `switch_conditional.ink` compiled. `outcome` = 2. The switch `{outcome: - 1: Arrested. - 2: Escaped. - else: Unknown.}` outputs `"Escaped."`.

#### 3: Else fallthrough
Same switch fixture. `outcome` = 5 (no matching case). Output is `"Unknown."`.

### UAT Scenarios (BDD)

#### Scenario: If-block true branch produced when condition holds
Given Ava has loaded a story with a block conditional `{ score > 10: You passed. - else: You failed. }`
And `score` is 11
When Ava calls `story.continue()`
Then `story.currentText` contains `"You passed."`
And `story.currentText` does not contain `"You failed."`

#### Scenario: Else branch produced when no condition holds
Given the same story with `score` set to 5
When Ava calls `story.continue()`
Then `story.currentText` contains `"You failed."`
And `story.currentText` does not contain `"You passed."`

#### Scenario: Switch dispatch selects matching case
Given a story with `{ outcome: - 1: Arrested. - 2: Escaped. - else: Unknown. }`
And `outcome` is 2
When Ava calls `story.continue()`
Then `story.currentText` contains `"Escaped."`

#### Scenario: Switch else fires when no case matches
Given the same switch story with `outcome` set to 99
When Ava calls `story.continue()`
Then `story.currentText` contains `"Unknown."`

#### Scenario: Block conditional output matches oracle
Given both Story and InkStory loaded from the same block-conditional fixture
When driven identically
Then every `Story.currentText` equals the corresponding `InkStory.currentText`

### Acceptance Criteria
- [ ] True branch text is output; false branch text is absent, for if/else blocks
- [ ] Correct switch case is selected when the value matches exactly
- [ ] Else fallthrough branch fires when no case matches
- [ ] Native runtime output matches JS-bridge oracle for all block/switch scenarios
- [ ] Save/restore round-trip produces identical branch selection

### Outcome KPIs
- **Who**: Swift developer using SwiftInkRuntime
- **Does what**: Runs stories with block and switch conditionals without host-app workarounds
- **By how much**: 100% of block/switch conditional branches in the test fixture produce correct output (0 mismatches vs oracle)
- **Measured by**: Oracle comparison test
- **Baseline**: 0% correct (feature not wired)

### Technical Notes
- Block conditionals in inklecate JSON likely use a conditional divert or a branch jump after the `ev`/`/ev` evaluation block — inspect compiled output before implementing.
- Switch dispatch may use repeated `==` comparisons on `evalStack` with conditional diverts per case.
- Dependencies: C1 (inline conditional evaluator) — block conditionals share the eval stack machinery.
- Brief coverage: rows 23–24 of the Feature Coverage Matrix.

---

## Story C3 — Ink Functions Return Values Correctly

### Problem
Ava is writing an Ink story that uses Ink functions (`=== function greet(name) ===`) called inline via `{greet("Cass")}`. The engine does not support function call frames — it either outputs the literal `"void"`, leaves the output stream unchanged, or errors — making The Intercept's function-based text composition broken.

### Who
- Ava — Swift developer building a narrative game
- Authoring a story that uses Ink functions for reusable text generation
- Motivated by The Intercept (2 functions used; required for ceiling proof)

### Solution
Extend `TreeWalker` and `InkEngine` to handle the `f()` divert (function call) and `~ret` (function return) opcodes. The return value is pushed onto `evalStack` when the function exits so the caller can push it to the output stream or assign it to a variable.

### Elevator Pitch
Before: `{greet("Cass")}` outputs `"void"` or nothing — the function call is not dispatched and the return address is lost.
After: `story.continue()` returns `"Hello, Cass."` — the function executes, returns its value, and the value is interpolated into the output at the call site.
Decision enabled: Ava can use Ink's function abstraction for reusable narrative text without re-implementing it in the host app.

### Domain Examples

#### 1: Function call interpolated in output (happy path)
Fixture `functions.ink` compiled. Story reaches `{greet("Cass")}`. `story.continue()` returns `"Hello, Cass."`. No `"void"` literal appears.

#### 2: Function return value assigned to temp variable
Story contains `~ temp name = greet("Ava")`. After this line, `{name}` in the output produces `"Hello, Ava."`. The temp variable holds the function's return value.

#### 3: Save/restore across a function call
Ava saves immediately before a function call site. Restores into a fresh `Story`. The restored `story.continue()` calls the function and returns `"Hello, Cass."` — identical to the in-memory run.

### UAT Scenarios (BDD)

#### Scenario: Function return value appears in output at call site
Given Ava has loaded a story containing `{greet("Cass")}` where `greet` returns `"Hello, " + name + "."`
When Ava calls `story.continue()`
Then `story.currentText` contains `"Hello, Cass."`
And `story.currentText` does not contain `"void"`

#### Scenario: Function return value assigned to temp variable is readable
Given the story contains `~ temp result = greet("Ava")` followed by `{result}`
When Ava calls `story.continue()` through both lines
Then `story.currentText` on the second line contains `"Hello, Ava."`

#### Scenario: Function that returns void does not pollute output
Given a story contains a function call `{sideEffect()}` where `sideEffect` sets a variable and returns nothing
When Ava calls `story.continue()`
Then `story.currentText` does not contain `"void"`
And the side-effect variable is set correctly

#### Scenario: Function output matches oracle
Given both Story and InkStory loaded from the same function-containing fixture
When driven identically through the function call site
Then Story.currentText equals InkStory.currentText

#### Scenario: Save/restore before function call produces same output
Given Ava saves the story state immediately before a function call site
When the state is restored into a fresh Story
Then story.continue() on the restored story produces the same text as the in-memory run

### Acceptance Criteria
- [ ] Function return value is interpolated correctly at inline call site
- [ ] Return value assigned to temp variable is readable in subsequent output
- [ ] Void-returning function does not emit `"void"` into output
- [ ] Native runtime output matches JS-bridge oracle for all function-call scenarios
- [ ] returnStack depth is balanced (equal before and after each function call)
- [ ] Save/restore round-trip across a function call produces identical output

### Outcome KPIs
- **Who**: Swift developer using SwiftInkRuntime
- **Does what**: Runs stories that use Ink functions for text composition without patching host app
- **By how much**: 100% of function-call output lines in the test fixture match oracle (0 mismatches)
- **Measured by**: Oracle comparison test + explicit `"void"` absence assertion
- **Baseline**: 0% correct (feature not wired)

### Technical Notes
- `f()` divert in JSON: `{"f()": "path.to.function"}` — pushes return address to `returnStack` then diverts.
- `~ret` control command pops `returnStack` and diverts to the return address.
- `"void"` is a JSON value that must be consumed without emitting to output when a void-returning function `~ret`s.
- Dependencies: none within the conditional text sub-feature; within tunnels sub-feature this is a prerequisite for T3 (ref params need function call frames).
- Brief coverage: rows 29–30 of the Feature Coverage Matrix.

---

## Story T1 — Single-Level Tunnel Executes and Returns

### Problem
Ava is writing a story that uses Ink tunnels to reuse a scene from multiple locations (`-> question_room ->`). The engine does not implement the tunnel call/return mechanism — when a tunnel divert is encountered, the story either ends prematurely or continues into the tunnel content but never returns to the caller, breaking the story's flow.

### Who
- Ava — Swift developer building a narrative game
- Authoring a story with 8+ tunnels (matching The Intercept)
- Motivated by The Intercept ceiling: no real Ink story of non-trivial length can avoid tunnels

### Solution
Extend `TreeWalker` and `InkEngine` to handle the `->t->` divert (tunnel entry, pushes return address) and the `->->` control command (tunnel exit, pops return address and diverts back to caller).

### Elevator Pitch
Before: `-> question_room ->` enters the tunnel knot and the story stalls there — `->->` is unrecognised and the story never returns to the line after the tunnel call.
After: the tunnel body executes, `->->` pops the return address, and `story.continue()` on the next call returns the post-tunnel text from the calling knot.
Decision enabled: Ava can use tunnels to build reusable scene fragments without copy-pasting Ink content.

### Domain Examples

#### 1: Tunnel body text and return (happy path)
Fixture `tunnels.ink` compiled. Calling knot contains `Before tunnel.\n-> sub_room ->\nAfter tunnel.`. Three `continue()` calls return `"Before tunnel."`, `"Sub room content."`, `"After tunnel."` in that order.

#### 2: Multiple tunnel calls from different knots
Same fixture. Knot A calls `-> sub_room ->` and knot B also calls `-> sub_room ->`. Both callers receive `"After the room, ..."` continuation text. Neither caller receives the other's continuation.

#### 3: Save/restore across tunnel boundary
Ava saves after entering the tunnel (tunnel body in progress). Restores into fresh `Story`. `story.continue()` completes the tunnel and returns `"After tunnel."` — identical to in-memory run.

### UAT Scenarios (BDD)

#### Scenario: Tunnel body text appears after tunnel entry
Given Ava has loaded a story where knot A diverts `-> sub_room ->`
When Ava calls `story.continue()` to enter the tunnel
Then `story.currentText` contains the first line of `sub_room`

#### Scenario: Post-tunnel continuation text appears after tunnel exits
Given the story is inside the `sub_room` tunnel
When Ava calls `story.continue()` through the tunnel body until `->->`
Then the next `story.continue()` returns the text that follows the tunnel call in the caller knot

#### Scenario: Story does not end prematurely at tunnel exit
Given Ava drives the story through a tunnel
When `->->` is reached
Then `story.canContinue` is true immediately after tunnel exit
And the story ends only at the caller's natural `-> END` or `done` node

#### Scenario: Tunnel output matches oracle
Given both Story and InkStory loaded from the same tunnel fixture
When driven identically through the tunnel entry and exit
Then all continue() outputs match between Story and InkStory

#### Scenario: Save/restore inside tunnel produces same post-tunnel text
Given Ava saves the story state while inside the tunnel body
When she restores into a fresh Story and continues
Then the restored story produces the same post-tunnel text as the in-memory run

### Acceptance Criteria
- [ ] Tunnel body content is output correctly during tunnel execution
- [ ] After `->->`, `story.continue()` returns post-tunnel caller-knot text (not tunnel text)
- [ ] `story.canContinue` remains true after `->->` until the caller naturally ends
- [ ] `returnStack` depth is balanced (equal before and after each `->t->` / `->->` pair)
- [ ] Native runtime output matches JS-bridge oracle for all tunnel scenarios
- [ ] Save/restore across tunnel boundary produces identical continuation

### Outcome KPIs
- **Who**: Swift developer using SwiftInkRuntime
- **Does what**: Runs stories with tunnels without the story stalling or ending prematurely
- **By how much**: 100% of tunnel calls in the test fixture complete and return to the correct caller continuation (0 premature endings)
- **Measured by**: Oracle comparison test + `canContinue` assertion at each post-tunnel step
- **Baseline**: 0% correct (feature not wired; story stalls or ends prematurely)

### Technical Notes
- `->t->` divert JSON: `{"->t->": "path.to.tunnel"}` — push return address to `returnStack`, then divert.
- `->->` control command JSON: `"->->"` — pop from `returnStack`, divert to popped address.
- ADR-004 explicitly designed `returnStack` as `[String]` (array) to support tunnel nesting — the same field is reused here; no new `StoryState` fields required.
- Requires verifying the exact inklecate JSON encoding of the `->t->` pattern before implementing (it may differ from `f()` call encoding).
- Dependencies: C3 (functions) shares the same `returnStack` mechanism; T1 and C3 can ship independently but must not conflict.
- Brief coverage: row 34 of the Feature Coverage Matrix.

---

## Story T2 — Nested Tunnels Unwind Correctly

### Problem
Ava is writing a story where tunnel A calls tunnel B (`A -> B ->`). With only single-level tunnel support, the story loses the outer return address when the inner tunnel exits — the story returns to B's caller site but not to A's caller site, producing incorrect continuation text or premature ending.

### Who
- Ava — Swift developer building a story with nested reusable scene fragments
- Authoring a story with at least one two-level tunnel nesting (as used in The Intercept)
- Motivated by correctness: a broken nested tunnel corrupts all story flow after it

### Solution
No new mechanism is required — ADR-004's `returnStack: [String]` already supports nesting by design. This slice validates that the T1 implementation correctly pushes multiple frames and unwinds them LIFO.

### Elevator Pitch
Before: tunnel A calls tunnel B → B exits correctly to A's body, but when A exits, the wrong return address is used and the story jumps to the wrong knot or ends.
After: B exits into A's body; A exits into the original caller's continuation. Both continuations are correct.
Decision enabled: Ava can compose reusable scenes that themselves call other reusable scenes.

### Domain Examples

#### 1: Two-level nesting — correct outer return (happy path)
Fixture `nested_tunnels.ink`: caller → A → B → back to A body → back to caller body. Five `continue()` calls return caller-pre, A-pre, B-body, A-post, caller-post text in order.

#### 2: Three `returnStack` entries at peak depth
At the deepest point of the two-level nesting, `returnStack.count` is 2. After both `->->` exits, `returnStack.count` is 0.

#### 3: Save/restore at peak nesting depth
Ava saves while inside tunnel B (both A and caller return addresses on stack). Restores into fresh `Story`. Continuation is: B exits → A body → A exits → caller-post text. Identical to in-memory run.

### UAT Scenarios (BDD)

#### Scenario: Outer return address is not lost during inner tunnel execution
Given a story where knot Main calls `-> A ->`, and A calls `-> B ->`
When Ava drives the story through B's `->->` exit
Then the next continue() returns A's post-B continuation text (not Main's continuation)

#### Scenario: Both return addresses unwind in LIFO order
Given the story is at peak nesting inside B
When Ava calls continue() through B's `->->` and then A's `->->`
Then the second post-exit continue() returns Main's post-A continuation text

#### Scenario: returnStack is empty after all tunnels exit
Given all tunnels have exited
Then `story.returnStack` is empty (verifiable via @testable import)

#### Scenario: Nested tunnel output matches oracle
Given both Story and InkStory loaded from the same nested-tunnel fixture
When driven identically
Then all continue() outputs match

### Acceptance Criteria
- [ ] After inner tunnel exits, outer tunnel body continuation is produced (not caller's continuation)
- [ ] After outer tunnel exits, caller continuation is produced
- [ ] `returnStack.count` equals the current nesting depth at any point in execution
- [ ] `returnStack` is empty after all nesting levels exit
- [ ] Native runtime output matches JS-bridge oracle for all nested-tunnel scenarios
- [ ] Save/restore at peak nesting depth produces identical unwinding

### Outcome KPIs
- **Who**: Swift developer using SwiftInkRuntime
- **Does what**: Runs stories with nested tunnels without continuation-address corruption
- **By how much**: 100% correct continuation after each tunnel level exits (0 address corruptions vs oracle)
- **Measured by**: Oracle comparison + `returnStack.count` assertions at each depth
- **Baseline**: After T1, single-level tunnels work; nested case has not been tested

### Technical Notes
- No new components required — this slice is a correctness validation of ADR-004's design.
- `returnStack` must be inspectable in tests via `@testable import SwiftInkRuntime`.
- Dependencies: T1 (single-level tunnels) must ship first.
- Brief coverage: row 34 (nested tunnels subset) of the Feature Coverage Matrix.

---

## Story T3 — Reference Parameters Mutate Caller Variables

### Problem
Ava is writing an Ink story that uses `ref` parameters in functions (`=== function add(ref total, n) ===`). When the function runs and mutates its `ref` parameter, the caller's variable is not updated — it retains its original value — making any story relying on function-based variable mutation produce incorrect state.

### Who
- Ava — Swift developer building a narrative game
- Authoring functions that accumulate values or toggle flags via `ref` parameters
- Motivated by The Intercept's use of `ref` in its 2 functions

### Solution
Extend `InkDecoder` and `TreeWalker` to resolve variable pointer nodes `{"^var": "name", "ci": N}` to the correct callstack frame, and update the variable at that frame when an assignment occurs inside the function body.

### Elevator Pitch
Before: `add(ref score, 10)` does not change `score` in the caller — the engine ignores the variable pointer's context index and no mutation occurs.
After: after `add(ref score, 10)` runs, `{score}` in the output shows the incremented value.
Decision enabled: Ava can use function-based variable mutation without introducing workarounds in the host app.

### Domain Examples

#### 1: Single ref parameter mutation (happy path)
Fixture `ref_params.ink` compiled. `score` starts at 0. `add(ref score, 10)` is called. After the function returns, `{score}` outputs `"10"`.

#### 2: Multiple mutations in sequence
`add(ref score, 5)` called three times. After the third call, `{score}` outputs `"15"`.

#### 3: Save/restore after mutation
After `add(ref score, 10)`, Ava saves state. Restores into fresh `Story`. `{score}` still outputs `"10"`.

### UAT Scenarios (BDD)

#### Scenario: ref parameter mutation is visible in caller output after function returns
Given Ava has loaded a story where `add(ref score, 10)` is called with `score` starting at 0
When Ava calls `story.continue()` through the function call and the `{score}` output line
Then `story.currentText` contains `"10"`

#### Scenario: Multiple sequential ref mutations accumulate correctly
Given `add(ref score, 5)` is called three times consecutively
When Ava drives the story through all three calls and reads `{score}`
Then `story.currentText` contains `"15"`

#### Scenario: Save/restore preserves mutated variable
Given `score` has been mutated to 10 via a ref call
When Ava saves and restores into a fresh Story
Then `{score}` in the restored story outputs `"10"`

#### Scenario: Ref parameter output matches oracle
Given both Story and InkStory loaded from the same ref-parameter fixture
When driven identically
Then Story.currentText equals InkStory.currentText for all output lines

### Acceptance Criteria
- [ ] Caller variable is updated to the value assigned inside the function via `ref`
- [ ] Multiple sequential `ref` mutations accumulate correctly
- [ ] Variable pointer `ci` (context index) correctly identifies the callstack frame holding the variable
- [ ] Save/restore after ref mutation produces identical variable values
- [ ] Native runtime output matches JS-bridge oracle for all ref-parameter scenarios

### Outcome KPIs
- **Who**: Swift developer using SwiftInkRuntime
- **Does what**: Uses Ink functions with `ref` parameters for variable accumulation without host-app workarounds
- **By how much**: 100% of `ref` parameter mutations produce correct caller-side variable values (0 mismatches vs oracle)
- **Measured by**: Oracle comparison test + explicit variable value assertions
- **Baseline**: 0% correct (variable pointer not wired; caller variable unchanged)

### Technical Notes
- Variable pointer JSON: `{"^var": "name", "ci": N}` where `ci` is the callstack context index (0 = global, 1+ = local frame).
- This node type was noted in the spike findings (`spike/findings.md`) as "present in the JSON but only in complex choice expressions" — now required for ref params.
- Dependencies: C3 (function callstack frames must exist before ref params can resolve the frame).
- Brief coverage: row 35 of the Feature Coverage Matrix.

---

## Cross-cutting Acceptance Criterion (all stories)

**Full save/restore round-trip** — For every scenario above, verify the outcome is identical whether Ava:
- Ran the story continuously in memory, or
- Saved after every step and reloaded into a fresh `Story` instance before each action.

The engine's state after reload must be indistinguishable from the in-memory state at the same point in the story.

**Zero regressions** — After every slice ships, the full test suite (including all Tier 1 and Tier 2 tests) must remain green. A regression in an earlier tier blocks the current slice from merging.
