<!-- markdownlint-disable MD024 -->
# User Stories — native-move-to-knot

Feature type: Backend (library API addition)
Feature ID: native-move-to-knot

## System Constraints

The following constraints apply to every story in this feature:

1. **Save/restore invariant** — every behaviour must survive a `saveState()` → `restoreState()` round-trip into a fresh `Story` instance. No new `StoryState` field is added; this feature does not modify the serialisation format.
2. **Inklecate fixtures only** — test fixtures must be compiled from real Ink source using inklecate at `/Users/maartene/Downloads/inklecate_mac/inklecate`. No hand-crafted JSON.
3. **Zero regressions** — all existing Tier 1, Tier 2, and Tier 3 tests must remain green after this feature ships.
4. **No new runtime dependencies** — `SwiftInkRuntime` must remain dependency-free (Foundation only).
5. **macOS-arm64 only** — Linux CI deferred; test target is macOS-arm64.
6. **Swift Testing style** — all tests use backtick function-name style; string-label form is forbidden.
7. **Variables and visit counts are preserved** — `StoryState.variablesState` and `visitCounts` are NOT cleared on jump (matching C# `ChoosePathString` reference behaviour).
8. **JS-bridge parity** — `Story.moveToKnot` must produce the same `currentText` sequence as `InkStory.moveToKnitStitch` for the same fixture and the same jump target.

---

## Story US-01 — Jump to a Named Knot (Happy Path)

### Problem
Ava is building a narrative game where players can open a chapter-select screen and jump directly to a named scene. She finds it impossible to redirect a running `Story` to a specific knot: the only way is to reload the entire story from JSON and manually advance through chapters — a slow and fragile workaround.

### Who
- Ava — Swift developer building a narrative game
- Mid-execution of a running `Story`, wants to redirect to a named knot
- Motivated by chapter-select, debug jump, and scene-replay features in games

### Solution
Add `public func moveToKnot(_ knot: String, stitch: String? = nil) throws` to the `Story` facade. The engine resolves the knot path, resets execution state (callstack, output, choices, mode flags), sets `isEnded = false`, installs the new container pointer, and returns. The developer then calls `canContinue` and `continue()` as normal.

### Elevator Pitch
Before: redirecting to a named knot requires reloading the story JSON and replaying choices — slow and impossible to generalise for arbitrary jump targets.
After: `try story.moveToKnot("interrogation")` resets the engine state and positions the pointer at `interrogation`; the next `story.continue()` returns `"Detective Mills enters the room."`.
Decision enabled: Ava can implement chapter-select, debug-jump, and scene-replay in her game without workarounds.

### Domain Examples

#### 1: Jump to knot "interrogation" from mid-story (happy path)
Ava is running `TheIntercept.ink.json`. The story is three choices deep inside the `investigation` knot. She calls `try story.moveToKnot("interrogation")`. The call returns without error. `story.canContinue` is `true`. `story.continue()` returns the first line of the `interrogation` knot — matching what `InkStory.moveToKnitStitch("interrogation")` would return for the same fixture.

#### 2: Jump from an ended story to restart a knot
Ava has driven the story to `END` (`story.canContinue == false`, `story.isEnded == true`). She calls `try story.moveToKnot("prologue")` to replay the opening. The call succeeds. `story.canContinue` is `true`. `story.continue()` returns the prologue's first line.

#### 3: Jump to a knot that exists, then jump again to a different knot
Ava calls `try story.moveToKnot("interrogation")`, continues two lines, then calls `try story.moveToKnot("epilogue")`. Both jumps succeed. After the second jump, `story.continue()` returns the first line of `epilogue`, not any line from `interrogation`.

### UAT Scenarios (BDD)

#### Scenario: Jump to a valid knot positions the story at that knot
Given Ava has loaded a story containing a knot named "interrogation"
And she has continued at least once (story is mid-execution)
When Ava calls `story.moveToKnot("interrogation")`
Then the call does not throw
And `story.canContinue` is `true`
And `story.continue()` returns the first line of the "interrogation" knot

#### Scenario: Jump to a valid knot clears all active engine state
Given Ava has a story with active tunnel frames on the returnStack
And currentChoices is non-empty
When Ava calls `story.moveToKnot("epilogue")`
Then the call does not throw
And the first `story.continue()` does not return any text from before the jump
And no tunnel continuation executes after the jump

#### Scenario: Jump from an ended story reactivates canContinue
Given Ava has driven a story to its natural END
And `story.canContinue` is `false`
When Ava calls `story.moveToKnot("prologue")`
Then `story.canContinue` is `true`
And `story.continue()` returns the first line of "prologue"

#### Scenario: Jump output matches JS-bridge oracle
Given both `Story` (native) and `InkStory` (oracle) are loaded from the same inklecate-compiled fixture
When both execute `moveToKnot("interrogation")` and then `continue()`
Then `Story.currentText` equals `InkStory.currentText`

#### Scenario: Global variables are preserved across a jump
Given Ava has set a global variable `score` to 42 before the jump
When Ava calls `story.moveToKnot("epilogue")`
Then after `story.continue()`, the variable `score` still equals 42 in the engine state

### Acceptance Criteria
- [ ] `Story.moveToKnot(_:stitch:)` is a public throwing method with the signature `public func moveToKnot(_ knot: String, stitch: String? = nil) throws`
- [ ] After a successful call, `story.canContinue` is `true`
- [ ] After a successful call, `story.continue()` returns the first line of the target knot (matching oracle)
- [ ] After a successful call, `story.currentText` does not contain any text from before the jump
- [ ] The state fields cleared by the jump are: `returnStack`, `evalStack`, `currentChoices`, `outputStream`, `callFrameVariables`, `suppressNextNewline`, `isEnded` (set false), `inTagMode`, `tagAccumulator`, `inStringMode`, `stringAccumulator`
- [ ] The state fields preserved by the jump are: `variablesState`, `visitCounts`, `chosenChoiceTargets`
- [ ] Multiple consecutive jumps each fully reset state (no accumulation of stale frames)
- [ ] Jump succeeds even when the story is already ended (`isEnded == true`)

### Outcome KPIs
- **Who**: Swift developer using SwiftInkRuntime
- **Does what**: Redirects a running story to a named knot without reloading the story JSON
- **By how much**: 100% of `moveToKnot` calls to existing knots succeed without error; post-jump `continue()` output matches oracle (0 mismatches)
- **Measured by**: Oracle comparison test + assertion on `canContinue == true` after jump
- **Baseline**: Feature does not exist; only workaround is story reload (100% of developers must reload)

### Technical Notes
- New public method on `Story` facade (Story.swift); implementation delegated to a new `InkEngine.moveToKnot` internal method.
- `StoryError` gains a new case: `case knotNotFound(String)` — the associated value is the attempted path string.
- Path resolution: `root.namedContent[knot]` for knot-only; `root.namedContent[knot]?.namedContent[stitch]` for knot+stitch.
- State reset mirrors C# `ChoosePathString(path, resetCallstack: true)` — see feature request context for field-level detail.
- `containerStack` is replaced (not appended) with a single new frame for the target container.
- No new `StoryState` fields — this feature does not change the serialisation format.
- Dependency: none. This feature is independent of all Tier 1–3 stories; it adds to the public API surface of the already-complete engine.

---

## Story US-02 — Jump Throws knotNotFound for Non-Existent Knot

### Problem
Ava is implementing a chapter-select feature that reads knot names from a game config file. If a config entry contains a typo or refers to a knot that was renamed in a later Ink revision, the engine must tell her immediately — not silently do nothing, not produce wrong output, not crash.

### Who
- Ava — Swift developer, implementing a chapter-select UI backed by config-driven knot names
- Calling `moveToKnot` with a name that may not exist in the current story version
- Motivated by safe error handling: catch the error, log it, show a fallback

### Solution
When `moveToKnot` is called with a knot name that does not exist in the container tree, `InkEngine` throws `StoryError.knotNotFound(attemptedPath)` before performing any state mutation. The engine state remains in a defined (pre-jump) condition after the throw.

### Elevator Pitch
Before: passing a non-existent knot name to `moveToKnot` either silently does nothing or crashes — Ava has no way to detect and recover from a bad jump target.
After: `catch StoryError.knotNotFound(let path)` gives Ava the exact path that failed, so she can log it, alert the team, or show a fallback scene.
Decision enabled: Ava can safely wire a config-driven chapter-select without guarding every jump call with a manual lookup.

### Domain Examples

#### 1: Typo in knot name (happy path for error path)
Ava's config reads `"interrogaton"` (missing one letter). `try story.moveToKnot("interrogaton")` throws `StoryError.knotNotFound("interrogaton")`. Ava's catch block logs the error and falls back to the main menu.

#### 2: Renamed knot — old name no longer exists
A story update renamed knot `"lab"` to `"laboratory"`. A host app still calling `moveToKnot("lab")` catches `StoryError.knotNotFound("lab")` and surfaces a version mismatch warning.

#### 3: Empty knot name
`try story.moveToKnot("")` throws `StoryError.knotNotFound("")`. Engine state is unchanged.

### UAT Scenarios (BDD)

#### Scenario: Non-existent knot name throws knotNotFound
Given Ava has a story that does NOT contain a knot named "ghost_town"
When Ava calls `story.moveToKnot("ghost_town")`
Then `StoryError.knotNotFound("ghost_town")` is thrown
And `story.canContinue` is unchanged from before the call

#### Scenario: Non-existent stitch on existing knot throws knotNotFound with compound path
Given Ava has a story with knot "investigation" but no stitch "ghost_alley" within it
When Ava calls `story.moveToKnot("investigation", stitch: "ghost_alley")`
Then `StoryError.knotNotFound("investigation.ghost_alley")` is thrown

#### Scenario: Empty knot name throws knotNotFound
Given any loaded story
When Ava calls `story.moveToKnot("")`
Then `StoryError.knotNotFound("")` is thrown

#### Scenario: Engine state is unchanged after a failed jump
Given Ava's story is mid-execution with currentText from the last continue()
When Ava calls `story.moveToKnot("nonexistent")` and catches the error
Then `story.canContinue` has the same value as before the call
And calling `story.continue()` (if canContinue was true) returns the next line of the original flow

### Acceptance Criteria
- [ ] `StoryError` has a new case `knotNotFound(String)` — associated value is the attempted path
- [ ] Calling `moveToKnot` with a name not in `root.namedContent` throws `knotNotFound` with the knot name as associated value
- [ ] Calling `moveToKnot(_:stitch:)` where the stitch is not in the knot's `namedContent` throws `knotNotFound` with the compound `"knot.stitch"` path as associated value
- [ ] Calling `moveToKnot("")` throws `knotNotFound("") `
- [ ] No state mutation occurs before the throw (pre-jump state is preserved)
- [ ] `StoryError.knotNotFound` conforms to `Equatable` (for XCTAssertThrowsError matching)

### Outcome KPIs
- **Who**: Swift developer using SwiftInkRuntime
- **Does what**: Catches knot-not-found errors and responds gracefully without crashing
- **By how much**: 100% of invalid-knot calls throw a typed, catchable error (0 silent failures)
- **Measured by**: XCTAssertThrowsError test assertions on all invalid-path scenarios
- **Baseline**: Feature does not exist; invalid jump targets either crash or are silently ignored

### Technical Notes
- `StoryError.knotNotFound(String)` must be added to the existing enum in `Story.swift` and must conform to `Equatable` (the enum already derives `Equatable` — adding the new case is sufficient).
- The throw must occur before any state mutation in `InkEngine.moveToKnot` — resolve path first, then mutate.
- The empty-string case is handled by the general resolution failure path (empty string does not match any named content key).
- Dependency: US-01 must be in progress (same method, error branch).

---

## Story US-03 — Jump to a Knot + Stitch (Compound Path)

### Problem
Ava is building a story that uses stitches (`= stitch_name`) to subdivide long knots into named scenes. She needs to jump to `investigation.lab` not just `investigation` — calling `moveToKnot("investigation")` takes her to the knot's root, not the lab stitch she wants.

### Who
- Ava — Swift developer authoring a story with stitches inside knots
- Needs to jump directly to a stitch (sub-section) within a known knot
- Motivated by fine-grained navigation in multi-stitch knots

### Solution
When `stitch` is non-nil, `InkEngine.moveToKnot` builds the compound path `"knot.stitch"` and resolves `root.namedContent[knot]?.namedContent[stitch]`. If found, the same full state reset and pointer installation as US-01 occurs. If not found, throws `knotNotFound` as per US-02.

### Elevator Pitch
Before: `moveToKnot("investigation", stitch: "lab")` does not exist — Ava can only jump to the root of a knot, not to a specific stitch within it.
After: `try story.moveToKnot("investigation", stitch: "lab")` resolves `investigation.lab`, resets state, and the next `continue()` returns the first line of the `lab` stitch.
Decision enabled: Ava can implement fine-grained scene navigation across all stitches in her story's knots.

### Domain Examples

#### 1: Jump to knot + stitch (happy path)
`TheIntercept.ink` contains knot `investigation` with stitch `lab`. `try story.moveToKnot("investigation", stitch: "lab")` succeeds. `story.canContinue` is `true`. `story.continue()` returns the first line of `investigation.lab`.

#### 2: Jump to knot only (stitch: nil) — same as US-01
`try story.moveToKnot("investigation", stitch: nil)` is equivalent to `try story.moveToKnot("investigation")`. Both jump to the root of the knot.

#### 3: Jump with stitch to wrong stitch name
Knot `investigation` exists but has no stitch named `"dungeon"`. `try story.moveToKnot("investigation", stitch: "dungeon")` throws `StoryError.knotNotFound("investigation.dungeon")`.

### UAT Scenarios (BDD)

#### Scenario: Jump to knot + stitch positions story at that stitch
Given Ava has a story with knot "investigation" containing stitch "lab"
When Ava calls `story.moveToKnot("investigation", stitch: "lab")`
Then the call does not throw
And `story.canContinue` is `true`
And `story.continue()` returns the first line of the "lab" stitch

#### Scenario: Jump to knot with nil stitch jumps to knot root
Given Ava has a story with knot "investigation"
When Ava calls `story.moveToKnot("investigation", stitch: nil)`
Then the call does not throw
And `story.continue()` returns the first line of the "investigation" knot

#### Scenario: Compound path output matches JS-bridge oracle
Given both `Story` (native) and `InkStory` (oracle) are loaded from the same fixture
When both call the equivalent jump to "investigation.lab"
Then `Story.currentText` equals `InkStory.currentText` after the jump

#### Scenario: Non-existent stitch within valid knot throws knotNotFound
Given Ava has a story with knot "investigation" but no stitch "dungeon"
When Ava calls `story.moveToKnot("investigation", stitch: "dungeon")`
Then `StoryError.knotNotFound("investigation.dungeon")` is thrown

### Acceptance Criteria
- [ ] When `stitch` is non-nil, the compound path `"knot.stitch"` is resolved via `root.namedContent[knot]?.namedContent[stitch]`
- [ ] A successful compound-path jump produces `canContinue == true` and the stitch's first line on `continue()`
- [ ] When `stitch` is `nil`, behaviour is identical to a knot-only jump (no regression from US-01)
- [ ] Non-existent stitch on a valid knot throws `knotNotFound("knot.stitch")` with the compound path
- [ ] Compound-path output matches JS-bridge oracle

### Outcome KPIs
- **Who**: Swift developer using SwiftInkRuntime
- **Does what**: Jumps directly to a named stitch within a knot without manually advancing through the knot's pre-stitch content
- **By how much**: 100% of compound-path jumps to existing stitches succeed; output matches oracle (0 mismatches)
- **Measured by**: Oracle comparison test for compound-path jump
- **Baseline**: Only knot-root jumps possible (after US-01 ships); no stitch navigation

### Technical Notes
- Path construction: `let path = stitch != nil ? "\(knot).\(stitch!)" : knot`
- Resolution: `root.namedContent[knot]?.namedContent[stitch]` — stitches are stored as named content inside the knot container.
- No additional state reset logic — same reset as US-01.
- Dependency: US-01 (the core jump mechanism).

---

## Story US-04 — Save/Restore Round-Trip After a Jump

### Problem
Ava's game auto-saves after every narrative beat. If the player jumps to a new scene (via chapter-select), the auto-save must capture the post-jump state. When the player loads that save, the story must resume from the jumped-to location — not from the pre-jump location.

### Who
- Ava — Swift developer, game has an auto-save system using `saveState()` / `restoreState()`
- Save occurs after every `moveToKnot` + `continue()` sequence
- Motivated by correctness: a corrupted save file after a chapter jump destroys player progress

### Solution
After `moveToKnot` succeeds and at least one `continue()` is called, `saveState()` captures the post-jump state. Restoring into a fresh `Story` instance resumes correctly from the jumped-to location.

### Elevator Pitch
Before: If save/restore is broken after a jump, auto-saving immediately after chapter-select corrupts the save file — the player resumes from the wrong scene on next load.
After: `saveState()` after `moveToKnot("interrogation")` + `continue()` produces a save that, when restored, resumes from `interrogation` — identical to the in-memory story.
Decision enabled: Ava can safely auto-save after chapter jumps without a separate save-suppression guard.

### Domain Examples

#### 1: Save after jump, restore into fresh Story (happy path)
Ava calls `try story.moveToKnot("interrogation")`, then `story.continue()` (gets line 1 of interrogation). Then `let savedData = try story.saveState()`. Creates a fresh `Story` from the same JSON. Calls `try freshStory.restoreState(savedData)`. `freshStory.continue()` returns line 2 of `interrogation` — the same as the in-memory story.

#### 2: Save before jump (pre-jump state), restore
Ava saves state before the jump (pre-jump). Then calls `moveToKnot("interrogation")`. Restores from the pre-jump save. Story resumes from the pre-jump location, not from interrogation. This confirms saves are point-in-time snapshots.

#### 3: Save after second jump
Ava jumps to `interrogation`, continues once, jumps to `epilogue`, continues once, saves. Restore resumes from line 2 of `epilogue`.

### UAT Scenarios (BDD)

#### Scenario: Restore after jump resumes from jumped-to location
Given Ava has called `story.moveToKnot("interrogation")` and then `story.continue()`
When Ava saves state and restores into a fresh Story
Then `freshStory.continue()` returns the same text as the next `story.continue()` in the original instance

#### Scenario: Pre-jump save is not affected by later jump
Given Ava saves state before calling `story.moveToKnot("interrogation")`
When she restores the pre-jump save into a fresh Story
Then the restored story resumes from the pre-jump location, not from "interrogation"

#### Scenario: Save/restore after compound path jump works correctly
Given Ava calls `story.moveToKnot("investigation", stitch: "lab")` and then `story.continue()`
When she saves and restores into a fresh Story
Then the restored story continues from where the in-memory story left off within the "lab" stitch

### Acceptance Criteria
- [ ] `saveState()` called after `moveToKnot()` + `continue()` captures the post-jump execution position
- [ ] `restoreState()` from a post-jump save resumes from the correct location in the target knot
- [ ] Pre-jump saves are unaffected by a subsequent jump (saves are point-in-time snapshots)
- [ ] All state fields reset by the jump are not present in the save with their pre-jump values (stale frames do not survive the reset + save cycle)
- [ ] Save/restore after a compound-path (knot + stitch) jump works identically to a knot-only jump

### Outcome KPIs
- **Who**: Swift developer using SwiftInkRuntime
- **Does what**: Auto-saves after chapter jumps and restores correctly on next session
- **By how much**: 100% of save/restore round-trips after a jump resume from the correct post-jump location (0 location corruptions)
- **Measured by**: Explicit assertion that `freshStory.continue()` returns the same text as the in-memory story at the corresponding step
- **Baseline**: No jump feature exists; save/restore correctness is undefined for jump scenarios

### Technical Notes
- No new save/restore logic required — `StoryState` is already `Codable` and all affected fields are covered.
- The key invariant to verify: after `moveToKnot`, the `stackFrames` snapshot in `saveState()` reflects the post-reset single frame (target knot), not the pre-jump multi-frame state.
- Dependency: US-01 (core jump) must ship first.

---

## Cross-Cutting Acceptance Criterion (all stories)

**Full save/restore round-trip** — For every scenario above, verify the outcome is identical whether Ava:
- Ran the story continuously in memory, or
- Saved after every step and reloaded into a fresh `Story` instance before each action.

**Zero regressions** — After this feature ships, the full test suite (including all Tier 1, Tier 2, and Tier 3 tests — 154 tests in 26 suites) must remain green. Any regression blocks merge.

**JS-bridge parity** — For every jump scenario, `Story.moveToKnot` must produce the same `currentText` sequence as `InkStory.moveToKnitStitch` for the same fixture and same jump target.
