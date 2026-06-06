# Slice 04 — Invisible Default Fallthrough

**Goal**: When no visible choices remain, the story continues through the invisible default path automatically, without player input.

## IN Scope

- Invisible default choices never appear in the choice list shown to the player
- When an invisible default is the only remaining path, the story continues automatically
- Behaviour survives a save/restore round-trip

## OUT Scope

None — this is the final Tier 2 slice.

## Dependencies

Slice 01 should ship first, so tests can reach the "all once-only choices exhausted" state that triggers invisible-default fallthrough.

## Learning Hypothesis

Once all once-only choices in a scene have been picked, the story flows through the `+ []` path and emits the fallthrough text automatically. If the app is left with an empty choice list and `canContinue = false`, the engine is not detecting that an automatic continuation is available.

## Acceptance Criteria

1. An invisible default choice never appears in `currentChoices`.
2. When the only remaining path is an invisible default, the story auto-continues — the next `continue()` call produces the fallthrough text without any `chooseChoice` call.
3. When both visible and invisible default choices exist, only the visible choices are shown; the invisible default does not fire.
4. A scene where all once-only choices have been picked and only an invisible default remains never produces an empty `currentChoices` with `canContinue = false` simultaneously.
5. **Save/restore**: save before a scene where only an invisible default remains, reload — the subsequent `continue()` produces the same fallthrough text as an uninterrupted run.

## Effort Estimate

~2 hours

## Example Story (to be compiled with inklecate)

```ink
=== scene ===
- (gather)
* [Ask about the shop.] -> gather
+ [] The conversation drifts naturally to a close.
-> END
```

After "Ask about the shop." has been picked once, it is gone. The next time the story reaches the gather, only the invisible default path remains and it should fire automatically.
