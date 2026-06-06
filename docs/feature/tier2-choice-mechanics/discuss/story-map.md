# Story Map — tier2-choice-mechanics

## Backbone (User Activities — from the story author's perspective)

| Activity | What the author expects |
|----------|------------------------|
| **A1 — Write once-only choices** | `*` choices disappear after being picked; the player cannot repeat them |
| **A2 — Write sticky choices** | `+` choices always reappear; always-available options stay available |
| **A3 — Write conditional choices** | `* {condition}` choices appear only when the condition holds |
| **A4 — Write visit-count logic** | Text and choices that reference visit history reflect actual player history |
| **A5 — Write invisible fallthrough** | `+ []` paths fire automatically when nothing else remains |

## Walking Skeleton

Delivered by Tier 1: the engine boots, text flows, choices appear, save/restore works across a `chooseChoice` round-trip. The Tier 2 walking skeleton is the Cass story playing without phantom once-only choices — Slice 01 (A1+A2) is the minimum needed.

## Slices (each ≤1 day, each with a named learning hypothesis)

### Slice 01 — Once-Only and Sticky Choices (A1, A2)
Stories covered: Story 1

**Goal**: After picking a once-only choice, it is gone from the story. Sticky choices always return.

IN scope: once-only choices disappear after being picked; sticky choices persist; both behaviours survive save/restore.

OUT scope: conditional gating, visit counts, invisible defaults.

**Learning hypothesis**: The Cass story stops showing "Ask what he needs." after it has been asked. If it still reappears, the engine is not tracking which once-only choices have been taken.

Effort: ~4 hours

---

### Slice 02 — Conditional Choice Visibility (A3)
Stories covered: Story 2

**Goal**: Choices guarded by a condition are hidden when the condition is false and visible when it is true.

IN scope: conditional choices respect story variables; gating survives save/restore.

OUT scope: visit counts feeding conditions (that interaction is validated once Slice 03 lands).

**Learning hypothesis**: `* {metCass} [Thank you.]` disappears when `metCass` is false. If it still shows, the engine is not evaluating the condition at choice-collection time.

Effort: ~3 hours

---

### Slice 03 — Visit Count Logic (A4)
Stories covered: Story 3

**Goal**: The story knows how many times each location has been visited; text and choices conditioned on visit history work correctly.

IN scope: visit counts accumulate correctly on location entry; count-based conditions in text and choices evaluate correctly; counts survive save/restore.

OUT scope: invisible defaults.

**Learning hypothesis**: `{café > 1: You recognise the smell.}` appears on the second visit. If it stays absent, the engine is not counting entries or not exposing the count to conditional expressions.

Effort: ~3 hours

---

### Slice 04 — Invisible Default Fallthrough (A5)
Stories covered: Story 4

**Goal**: When no visible choices remain, the story continues through the invisible default without player input.

IN scope: invisible default choices are hidden from the player; the story auto-continues when they are the only path left; behaviour survives save/restore.

OUT scope: none; this is the last Tier 2 slice.

**Learning hypothesis**: Once all once-only choices have been picked, the story flows through the `+ []` path automatically. If the app gets stuck with an empty choice list, the engine is not triggering the auto-continuation.

Effort: ~2 hours

## Prioritization

| Priority | Slice | Rationale |
|----------|-------|-----------|
| 1 | Slice 01 | The Cass story is currently broken — once-only choices reappear every loop. Highest player-visible impact. |
| 2 | Slice 02 | Conditional choices are a foundational Ink idiom; the parsing side is done, only the runtime check is missing. |
| 3 | Slice 03 | Visit-count logic builds on the tracking work from Slice 01; needed for the `{knot > 0}` pattern common in real stories. |
| 4 | Slice 04 | A correctness edge case; no known story currently hangs on this, but it is required for scenes to close gracefully. |
