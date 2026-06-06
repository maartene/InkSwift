# Slice 03 — Visit Count Logic

**Goal**: The story knows how many times the player has visited each location; text and choices that depend on visit history work correctly.

## IN Scope

- The engine counts how many times each named location (knot, stitch) has been entered
- Conditional text that references visit history (`{café > 1: You recognise the smell.}`) evaluates correctly
- Counts survive a save/restore round-trip

## OUT Scope

- Invisible default auto-selection — Slice 04

## Dependencies

Slice 01 should ship first, since Slice 01 also touches how the engine records player actions. Building on a stable foundation avoids double-fixing the same area.

## Learning Hypothesis

`{café > 1: You recognise the smell now.}` appears on the second visit to the café. If it stays absent on every visit, the engine is not accumulating visit counts or not making them available to conditional expressions.

## Acceptance Criteria

1. The first entry into a named location is treated as visit number one; subsequent entries increment the count.
2. A location the player has never reached has a visit count of zero.
3. Conditional text conditioned on visit history (`{location > 0: ...}`) shows the right variant based on actual visit count.
4. A conditional choice conditioned on a visit count appears and disappears correctly as the count changes (integration with Story 2 / Slice 02).
5. **Save/restore**: save mid-story with a non-zero visit count, reload — visit-count-based text and choices produce the same output as an uninterrupted run.

## Effort Estimate

~3 hours

## Example Story (to be compiled with inklecate)

```ink
=== café ===
{café > 1: You recognise the smell now.}
You enter the café.
-> END
```
