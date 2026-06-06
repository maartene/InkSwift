# Slice 01 — Once-Only and Sticky Choices

**Goal**: After picking a once-only choice, it is gone from the story. Sticky choices always return.

## IN Scope

- Once-only choices (`*`) are absent from the choice list after being picked
- Sticky choices (`+`) remain in the choice list after being picked
- Both behaviours survive a save/restore round-trip

## OUT Scope

- Conditional choice gating — Slice 02
- Visit-count logic and CNT? — Slice 03
- Invisible default auto-selection — Slice 04

## Learning Hypothesis

The Cass story stops showing "Ask what he needs." after the player has already asked it. If the choice still reappears, the engine is not recording which once-only choices have been taken.

## Acceptance Criteria

1. After picking a once-only choice and looping back to the same branch point, that choice is absent from `currentChoices`.
2. After picking a sticky choice and looping back, that choice is still present in `currentChoices`.
3. Picking one once-only choice from a list of three removes only that choice; the remaining two are still available.
4. A scene with one sticky and two once-only choices ends with only the sticky choice after both once-only options have been picked.
5. **Save/restore**: pick a once-only choice, save, reload, loop back — the choice does not reappear.
6. **Save/restore**: pick a sticky choice, save, reload, loop back — the choice is still available.

## Effort Estimate

~4 hours

## Example Story (to be compiled with inklecate)

```ink
=== choice_loop ===
- (gather_point)
* [Ask about the shop.] -> gather_point
* [Ask what he needs.] -> gather_point
+ [Order a coffee.] -> gather_point
-> END
```
