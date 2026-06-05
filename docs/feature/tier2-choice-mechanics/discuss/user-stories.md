# User Stories — tier2-choice-mechanics

Feature type: Backend (engine mechanics)
Feature ID: tier2-choice-mechanics

Cross-cutting constraint (all stories): **Save/restore invariant** — every behaviour must survive
a save-and-reload cycle. The game can be quit and resumed at any point; when it resumes, the
story behaves exactly as it would have if the player had never left.

---

## Story 1 — Once-Only and Sticky Choices Behave Differently

**As a** story author writing in Ink,
**I want** `*` (once-only) choices to disappear after the player picks them, and `+` (sticky) choices to always remain available,
**so that** the player feels the story remembers what they have already done.

### Elevator Pitch
Before: picking "Ask what he needs." and then looping back to the same scene shows the question again, as if the player never asked it — the story has no memory.
After: pick a once-only choice, loop back → `story.currentChoices` does not contain that choice. Pick a sticky choice, loop back → `story.currentChoices` still contains that choice.
Decision enabled: a story author can write `*` vs `+` in Ink and trust the engine to enforce the distinction, without any filtering code in the host app.

### Acceptance Criteria

1. **Once-only is removed after pick** — After the player picks a once-only choice and the story loops back to the same branch point, that choice is absent from `currentChoices`.
2. **Sticky persists after pick** — After the player picks a sticky choice and the story loops back, that choice is still present in `currentChoices`.
3. **Multiple once-only choices** — Picking one once-only choice from a list removes only that choice; the others remain until each is picked.
4. **Mixed list converges** — A scene with one sticky and two once-only choices ends with only the sticky choice remaining after both once-only choices have been picked.
5. **Save/restore: once-only stays gone** — Save the story after picking a once-only choice. Reload into a fresh story instance. Loop back to the same branch point. The picked choice does not reappear.
6. **Save/restore: sticky stays available** — Save after picking a sticky choice. Reload. Loop back. The sticky choice is still available.

---

## Story 2 — Conditional Choices Respect Story State

**As a** story author writing choices guarded by a condition (`* {condition} [text]`),
**I want** those choices to appear only when the condition is true,
**so that** players are never offered options that make no sense in the current state of the story.

### Elevator Pitch
Before: `* {metCass} [Thank you for the coffee.]` appears in the choice list even when the player has never met Cass — the story offers an option the player has no basis to take.
After: set the relevant story variable to false → `story.currentChoices` does not contain the guarded choice. Set it to true → the choice appears.
Decision enabled: a story author can gate choices on story variables and trust the engine to filter them, rather than writing filtering logic in the host app.

### Acceptance Criteria

1. **False condition excluded** — A choice guarded by a condition that evaluates to false is absent from `currentChoices`.
2. **True condition included** — The same choice with a true condition is present in `currentChoices`.
3. **Variable-driven condition** — Setting a story variable to true causes a previously absent conditional choice to appear; setting it back to false removes it again.
4. **No side effects on unconditional choices** — Choices without a condition are unaffected; they always appear regardless of any variable state.
5. **Save/restore: gating reflects restored state** — Save with the condition false (choice absent). Reload. The choice is still absent. Save with condition true (choice present). Reload. The choice is still present.

---

## Story 3 — Stories Can React to How Often a Location Has Been Visited

**As a** story author writing text or choices that change on revisit (`{café > 0: You've been here before.}`),
**I want** the engine to track how many times the player has visited each part of the story,
**so that** Ink's visit-count idiom works and the story world feels like it has memory.

### Elevator Pitch
Before: `{café > 1: You recognise the smell now.}` never shows its alternate text, even on a second visit — the story cannot tell the difference between first and subsequent visits.
After: visit a location twice → `story.continue()` on the second visit produces the alternate text that the condition guards.
Decision enabled: a story author can write stories where revisiting a location changes what is said, a fundamental Ink idiom for living, reactive worlds.

### Acceptance Criteria

1. **First visit counted** — After entering a named location for the first time, the story treats that location's visit count as 1.
2. **Subsequent visits accumulate** — Each re-entry increments the count; the story can distinguish first, second, and third visits in its text and choices.
3. **Unvisited is zero** — A location the player has never reached has a visit count of zero; conditions based on it evaluate accordingly.
4. **Visit-count conditions in text** — Inline conditional text like `{café > 1: ...}` evaluates correctly based on actual visit history.
5. **Save/restore: counts survive** — Save mid-story with a non-zero visit count. Reload. Visit-count-based text and choices produce the same output as if the player had never saved.

---

## Story 4 — Invisible Default Choices Flow Through Automatically

**As a** story author writing scenes that should transition automatically when no choices remain (`+ []`),
**I want** invisible default choices to fire on their own without player input,
**so that** the story never shows the player a blank or missing choice list when a natural continuation exists.

### Elevator Pitch
Before: once all once-only choices in a scene have been picked, the story presents an empty choice list and the app has no way to continue — the game is stuck.
After: once only the invisible default path remains, `story.continue()` produces the fallthrough text without the player choosing anything; `currentChoices` is never empty while a continuation is available.
Decision enabled: a story author can write `+ []` fallthrough transitions and trust the engine to handle them invisibly, with no special-case code in the host app.

### Acceptance Criteria

1. **Invisible defaults absent from choice list** — An invisible default choice never appears in `currentChoices`.
2. **Auto-continuation when only defaults remain** — When all visible choices have been exhausted and only an invisible default is left, the story continues automatically; no `chooseChoice` call is needed.
3. **Visible choices take priority** — When both visible and invisible default choices exist, only the visible choices are offered; the invisible default does not fire.
4. **No empty-list hang** — A scene where all once-only choices have been picked and an invisible default is the sole remaining path never produces an empty `currentChoices` paired with `canContinue = false`.
5. **Save/restore: auto-continuation produces same text** — Save before a scene whose only remaining path is an invisible default. Reload. The subsequent `continue()` produces the same text as in an uninterrupted run.

---

## Cross-cutting Acceptance Criterion (all stories)

**Full save/restore round-trip** — For every scenario above, verify the outcome is identical whether the player:
- Ran the story continuously in memory, or
- Saved after every step and reloaded into a fresh story instance before each action.

The engine's state after reload must be indistinguishable from the in-memory state at the same point in the story.
