# Journey Visual — native-move-to-knot

Feature ID: native-move-to-knot
Persona: Ava — Swift developer building a narrative game with `SwiftInkRuntime`
Goal: Programmatically jump to a specific knot (or stitch) in a running story

---

## What this feature enables

An Ink story is a branching narrative made up of named sections called **knots** (and sub-sections called **stitches**). Normally the runtime advances through the story sequentially, following diverts and choices. But there are many situations where an app needs to jump to a specific location directly — bypassing the normal flow:

- A **table of contents** or chapter-select screen lets the player jump straight to any scene
- A **"replay this chapter"** button restarts from a known knot
- A **branching game mechanic** routes the player to a side path based on inventory, time of day, or an external event
- A **developer debugging tool** skips to a specific scene without replaying everything before it

`moveToKnot(_:stitch:)` provides this capability for the native Swift runtime.

### Parity with the C# reference implementation

This function must behave identically to `ChoosePathString(path, resetCallstack: true)` in the official Ink C# runtime. That method is the established contract that all Ink runtimes are expected to honour. The same behaviour is already available in InkSwift's JS-bridge layer via `InkStory.moveToKnitStitch(_:stitch:)` — this feature brings parity to the native Swift runtime so developers can switch runtimes without changing application code.

The C# contract means:
- The **call stack is fully reset** before the jump (no lingering tunnels or function frames from the previous position)
- **Choices, output buffer, and eval stack are cleared** — the story starts cleanly from the new location
- **Variables and visit counts are preserved** — game state carries over; only execution position changes
- The jump **throws** (and leaves state untouched) if the target knot or stitch does not exist

---

## Developer Journey Flow

```
[Story loaded]
     |
     v
[Continue through opening]          canContinue == true
     |
     v
[Trigger: scene change needed]      e.g. player opens chapter select,
     |                              or game event routes to side path
     v
[Call moveToKnot(_:stitch:)]        story.moveToKnot("interrogation")
     |                              story.moveToKnot("investigation", stitch: "lab")
     v
+-- knot/stitch exists? ----YES---> [Engine resets state]
|                                        * callstack cleared
|                                        * choices / evalStack cleared
|                                        * outputStream cleared
|                                        * mode flags reset
|                                        * isEnded = false
|                                        * pointer set to target container
|                                   [canContinue == true]
|                                        |
|                                        v
|                                   [Developer calls continue()]
|                                        |
|                                        v
|                                   [Story resumes from new location]
|
+-- knot/stitch NOT found? --NO---> [throws StoryError.knotNotFound]
                                        * story state unchanged? NO
                                          (reset must still be safe to inspect)
                                        * developer catches error,
                                          logs or shows fallback UI
```

---

## Knot-Only vs Knot+Stitch Path Construction

```
moveToKnot("cliffhanger")
  -> resolves path: "cliffhanger"

moveToKnot("investigation", stitch: "lab")
  -> resolves path: "investigation.lab"

moveToKnot("investigation", stitch: nil)
  -> resolves path: "investigation"
```

---

## State Reset Sequence (mirrors C# ChoosePathString)

```
Before jump:
  containerStack:      [...active frames...]
  returnStack:         [...maybe frames...]
  evalStack:           [...maybe values...]
  currentChoices:      [...maybe choices...]
  outputStream:        [...maybe buffered text...]
  callFrameVariables:  [...maybe frames...]
  isEnded:             maybe true/false

After moveToKnot() succeeds:
  containerStack:      [frame pointing to target knot/stitch]
  returnStack:         []
  evalStack:           []
  currentChoices:      []
  outputStream:        []
  callFrameVariables:  []
  suppressNextNewline: false
  isEnded:             false
  canContinue:         true  (assuming target has content before END)
```

---

## Error Path

```
story.moveToKnot("nonexistent_knot")
    -> InkDecoder / container tree lookup fails
    -> throws StoryError.knotNotFound("nonexistent_knot")

story.moveToKnot("town", stitch: "ghost_alley")
    -> knot "town" exists, stitch "ghost_alley" does not exist
    -> throws StoryError.knotNotFound("town.ghost_alley")
```

---

## Integration Checkpoints

| Checkpoint | What to validate |
|------------|-----------------|
| Path resolution | `root.namedContent["knot"]` exists; for stitches, `knot.namedContent["stitch"]` exists |
| State reset completeness | All 8 state fields listed above are cleared/reset before pointer install |
| canContinue post-jump | `canContinue == true` after successful jump to a knot with content |
| save/restore compatibility | After moveToKnot + continue(), saveState/restoreState round-trip produces same output |
| Error does not corrupt | After a failed jump (knotNotFound), story is in a defined state |
| JS-bridge parity | `Story.moveToKnot` output matches `InkStory.moveToKnitStitch` output from same fixture |
