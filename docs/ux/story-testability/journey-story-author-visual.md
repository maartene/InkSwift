# Journey Visual: Ink Story Unit Testing

**Persona**: Raya — Swift developer and Ink story author  
**Goal**: Write automated Given-When-Then tests that verify story logic without playing through the whole story  
**Feature**: story-testability  

---

## Emotional Arc

```
FRUSTRATION          CONTROL              CONFIDENCE
     |                   |                    |
     v                   v                    v
[Brittle tests]   [State injection]    [Green test suite]
 Choice indices    Direct API calls    Logic bugs caught
 break on reorder  set preconditions   before players see
```

**Start**: Frustrated — existing tests replay choices; one reorder breaks everything  
**Middle**: Focused and in control — state injected directly; no fragile setup chain  
**End**: Confident — story logic is provably correct; test suite is a safety net  

---

## Happy Path Flow

```
Step 1             Step 2              Step 3              Step 4
Load Story    →   moveToKnot      →   setVariable     →   setVisitCount
                  (GIVEN:            (GIVEN:             (GIVEN:
                   navigate)          inject vars)        inject counts)

   Story(json:)   moveToKnot(       setVariable(        setVisitCount(
                   "reward_check")   "score", to: 10)    forKnot: "prologue",
                                                         to: 2)

Feels:            Feels:             Feels:              Feels:
Neutral/ready     Positioned         In control          Fully set up
```

```
Step 5                   Step 6
continueMaximally()  →   #expect assertions
(WHEN: execute)          (THEN: verify)

let output =             #expect(output.contains(
  story.continueMaximally()  "You earned the gold badge."))
                         #expect(
                           story.getVariable("badge_awarded")
                           as? Bool == true)

Feels:                   Feels:
Anticipating             Confident (green) or
                         Informed (red = story bug)
```

---

## Full Journey ASCII Flow

```
+---------------------------------------------------------------+
|  GIVEN — Set Up Test State                                    |
|                                                               |
|  1. Story(json: storyJSON)                                    |
|     -> story instance created                                 |
|                                                               |
|  2. try story.moveToKnot("reward_check")                      |
|     -> canContinue == true                                    |
|     -> currentChoices is empty                                |
|                                                               |
|  3. story.setVariable("score", to: 10)                        |
|     -> getVariable("score") returns 10                        |
|     -> unknown variable: silent no-op, returns nil            |
|                                                               |
|  4. story.setVisitCount(forKnot: "prologue", to: 2)           |
|     -> visitCount(forKnot: "prologue") returns 2              |
|     -> unknown knot: silent, returns 0                        |
+---------------------------------------------------------------+
                              |
                              v
+---------------------------------------------------------------+
|  WHEN — Execute                                               |
|                                                               |
|  5. let output = story.continueMaximally()                    |
|     -> drains all lines until canContinue == false            |
|     -> or stops at choice point                               |
|     -> returns concatenated output string                     |
+---------------------------------------------------------------+
                              |
                              v
+---------------------------------------------------------------+
|  THEN — Verify                                                |
|                                                               |
|  6a. #expect(output.contains("You earned the gold badge."))   |
|  6b. #expect(story.getVariable("badge_awarded") as? Bool      |
|            == true)                                           |
|  6c. #expect(story.currentChoices.count == 2)  // optional    |
+---------------------------------------------------------------+
```

---

## Error Paths

### Variable Name Not Found

```
story.setVariable("ghost_var", to: 42)
// -> silent no-op (no throw)
// -> getVariable("ghost_var") returns nil
// -> Ink runtime ignores unknown variables
// -> test uses optional chaining or as? cast
```

**Recovery**: Story author checks VAR declaration spelling in .ink source.

### Visit Count for Unknown Knot

```
story.setVisitCount(forKnot: "nonexistent", to: 5)
// -> silent no-op (write) — no throw
story.visitCount(forKnot: "nonexistent")
// -> returns 0 (read) — no throw
```

**Recovery**: Story author checks knot name spelling in .ink source.

### continueMaximally on Ended Story

```
// story.canContinue == false (story already ended)
let output = story.continueMaximally()
// -> returns "" immediately
// -> canContinue remains false
```

**Recovery**: Story author calls moveToKnot before continueMaximally.

### moveToKnot Precedes setVariable

The jump order matters: `moveToKnot` resets execution state (stacks, output, choices) but preserves `variablesState` and `visitCounts`. Call `moveToKnot` first, then set variables — the variables survive the jump. Setting variables before `moveToKnot` is equally valid (variables are preserved).

---

## Shared Artifacts Registry

| Artifact | Source | Consumers | Risk |
|---|---|---|---|
| `$story` | `Story(json:)` | All API calls | LOW — init is well-tested |
| `$knotName` | String matching inklecate knot ID | `moveToKnot`, `setVisitCount`, `visitCount` | MEDIUM — name typo silently misses |
| `$varName` | String matching VAR declaration | `setVariable`, `getVariable` | MEDIUM — name typo returns nil silently |
| `$varValue` | Test precondition value | `setVariable`, `getVariable`, `#expect` | LOW — author controls this |
| `$output` | `continueMaximally()` return | `#expect(output.contains(...))` | LOW — single source |
| `$expectedOutput` | String literal from .ink source | `#expect` assertion | MEDIUM — must stay in sync with .ink |

---

## Test Structure Model (Swift Testing)

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

@Test func `score below 10 does not award badge`() throws {
    // GIVEN
    let story = try Story(json: storyFixtureJSON)
    try story.moveToKnot("reward_check")
    story.setVariable("score", to: 5)

    // WHEN
    let output = story.continueMaximally()

    // THEN
    #expect(!output.contains("gold badge"))
    #expect(story.getVariable("badge_awarded") as? Bool != true)
}

@Test func `returning visitor sees different greeting`() throws {
    // GIVEN
    let story = try Story(json: storyFixtureJSON)
    try story.moveToKnot("greeting")
    story.setVisitCount(forKnot: "greeting", to: 3)

    // WHEN
    let output = story.continueMaximally()

    // THEN
    #expect(output.contains("Welcome back again!"))
}
```

---

## Integration Checkpoints

1. **Step 1 → 2**: `moveToKnot` requires a loaded Story; cannot be called before `init`.
2. **Step 2 → 3/4**: `setVariable` and `setVisitCount` work regardless of execution position; `moveToKnot` is not a prerequisite for them, but calling it after preserves the injected values (variables/visitCounts are preserved across jump).
3. **Step 3/4 → 5**: `continueMaximally` must be called after all GIVEN setup; calling it before `moveToKnot` would execute from the wrong position.
4. **Step 5 → 6**: `getVariable` reads post-execution state; call it after `continueMaximally`, not before.

---

## Comparison: Old Approach vs New Approach

```
OLD (fragile):                    NEW (robust):
─────────────────────────         ─────────────────────────
story.continue()                  try story.moveToKnot("reward_check")
story.chooseChoice(at: 0)         story.setVariable("score", to: 10)
story.continue()                  let output = story.continueMaximally()
story.chooseChoice(at: 1)         #expect(output.contains("gold badge"))
story.continue()
story.chooseChoice(at: 0)         No choice indices.
// ... 10 more setup steps         No fragile chain.
#expect(story.currentText         Test survives story refactoring.
  .contains("gold badge"))

PROBLEM: Any choice addition       BENEFIT: Tests verify logic,
breaks the index chain.            not incidentally-correct paths.
```
