# Slice 02 — Conditional Choice Visibility

**Goal**: Choices guarded by a condition are hidden when the condition is false and visible when it is true.

## IN Scope

- Conditional choices respect the current value of story variables
- The condition is evaluated at the moment choices are collected, using the current story state
- Gating behaviour survives a save/restore round-trip

## OUT Scope

- Conditions that reference visit counts (that interaction is exercised once Slice 03 lands)
- Any change to how conditions are expressed in Ink source

## Learning Hypothesis

`* {metCass} [Thank you for the coffee.]` is absent from the choice list when `metCass` is false and present when it is true. If it always appears regardless of the variable, the engine is not checking the condition before adding the choice.

## Acceptance Criteria

1. A conditional choice is absent from `currentChoices` when its condition evaluates to false.
2. The same choice is present in `currentChoices` when the condition evaluates to true.
3. Setting a story variable to true causes a previously absent conditional choice to appear on the next loop.
4. Setting it back to false removes the choice again.
5. Choices without a condition are unaffected — they always appear regardless of variable state.
6. **Save/restore**: save with condition false (choice absent), reload — choice is still absent. Save with condition true (choice present), reload — choice is still present.

## Effort Estimate

~3 hours

## Example Story (to be compiled with inklecate)

```ink
VAR metCass = false

=== start ===
~ metCass = false
* {metCass} [Thank you for the coffee.]
    You already know each other.
* [Hello.]
    Meeting for the first time.
-> END
```
