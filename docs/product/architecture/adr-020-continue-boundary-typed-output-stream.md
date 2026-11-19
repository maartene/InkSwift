# ADR-020: Continue Boundary — Typed Output Stream, Per-Line Tags, Flow-End Reason

**Status**: Accepted (maintainer, 2026-11-19 — option A1; A2 deferred to its own feature). Revised after design review, 2026-11-19.
**Date**: 2026-11-19
**Deciders**: Maarten Engels (project owner), Morgan (solution architect)
**Feature**: reference-fidelity-backlog (issues #30, #28)
**Amends**: ADR-018 (adds one *optional* save key); ADR-017 (`refusePop` routes through the shared `forceEnd()`)

---

## Context

The C# runtime's `Story.ContinueInternal` brackets every `Continue()` with two steps
(`Story.cs:443-444`, `502-516`):

- a **prologue**: `ResetOutput()`, and `didSafeExit = false`;
- an **epilogue**: when the story cannot continue, it reports an error chosen by the
  call-stack top, but only if all of these hold: `generatedChoices.Count == 0`,
  `!didSafeExit`, and `_temporaryEvaluationContainer == null`.

`didSafeExit` is set in three places: by `done` (`Story.cs:1555`), by `ForceEnd`
(`StoryState.cs:1194`), and by a function evaluated from the game ending. `end` calls
`ForceEnd`, and every runtime error goes through `AddError`, which also calls `ForceEnd`. So
**a story that ended with an error never also gets the end-of-content error**.

Tags are `BeginTag`/`EndTag` objects *inside* the output stream, and `currentTags` is derived
from that stream (`StoryState.cs:355-414`). A tag that follows a newline ends that line
(`Story.cs:689-718`).

InkSwift has neither half:

- Tags live in a list beside an untyped `[String]` output stream (`TreeWalker.swift:103`,
  `StoryState.swift:320`). Only `chooseChoice` clears that list (`InkEngine.swift:863`), and
  `moveToKnot` doesn't (#30). The lookahead in `mayFlushLine` also attaches a tag that
  *starts* the next line to the current one.
- `done` and `end` both set `isEnded` and `pointer.index = Int.max` (`TreeWalker.swift:212-214`).
  Running off the end is a bare `.stop` (`InkEngine.swift:227-243`). `refusePop`
  (`InkEngine.swift:383-388`, ADR-017) sets `isEnded` and clears the choices and the return
  stack, but nothing marks a safe exit (#28).
- `isEnded` is a **persisted** save field (`StoryState.swift:325, 410, 425, 450`).

The engine also has one stop with no C# counterpart: when a choice's continuation root runs
out (`isChoiceContinuationRoot`, `InkEngine.swift:228-234`), the loop stops instead of popping
into the parent. In C#, a choice body is a named-only container (`c-N`). Running off its end
fails `IncrementContentPointer` (`indexInAncestor == -1`, `Story.cs:2727-2729`), so the
pointer becomes null: that is a *ran-out* stop.

## Decision

Option **A1**: keep the existing lookahead loop and add the C# boundary around it.

1. **Typed output stream in memory.** Each item is *text*, *newline* or *tag*.
   - Glue removes trailing newlines but stops at a tag, as C# `TrimNewlinesFromOutputStream`
     stops at a control command.
   - The `nop` trim and newline de-duplication look at text items only.
   - A tag item is created when the tag *closes* (`/#`). A tag still open at a save boundary
     is carried by the existing `inTagMode` / `tagAccumulator` keys, as today.
2. **Line extraction is one pure function**: stream in; line text, line tags and the
   remainder out.
   - Tags before the first newline belong to the line.
   - Tags after the first newline stay in the remainder.
   - `currentTags` reports the tags of the line `continue()` just returned.
3. **Prologue** in `InkEngine.step()`: clear the line tags and set `safeExit = false`.
   `chooseChoice` and `moveToKnot` also clear the line tags.
4. **Stop state.**
   - `isEnded` keeps its meaning (the flow has stopped) **and its wire key**.
   - Two new fields are **transient**: they live in the engine, are reset in the prologue and
     are never saved.
     - `safeExit: Bool`
     - `stopReason`: *safeExit* or *ranOut*
   - **One `forceEnd()`** is shared by `end` and by `refusePop` (and any later runtime error).
     It clears the choices, resets the return stack, sets `isEnded` and `pointer.index = Int.max`,
     and sets `safeExit = true`. This is C# `ForceEnd`.
   - `done` sets `isEnded`, `pointer.index = Int.max` and `safeExit = true`, and keeps the
     choices.
   - **Ran out** means the loop stopped because the container stack exhausted with no
     invisible default to fire. Two cases:
     - the root frame popped empty;
     - a choice-continuation root exhausted (`InkEngine.swift:228-234`), the C#
       named-container null-pointer case.

     Both set `isEnded`, with `safeExit` still false.
5. **Epilogue.** It runs **only for a ran-out stop**, and fires when `currentChoices` is
   empty and `safeExit` is false. That is C#'s condition with
   `_temporaryEvaluationContainer == null` always true: InkSwift has no `EvaluateFunction`.
   If one is added, it must suppress the epilogue. The epilogue appends the exact C# message,
   chosen by the return-stack top:
   - tunnel → "unexpectedly reached end of content. Do you need a '->->' to return from a tunnel?"
   - function → "unexpectedly reached end of content. Do you need a '~ return'?"
   - empty → "ran out of content. Do you need a '-> DONE' or '-> END'?"

   The C# "unknown reason" branch needs threads, so it is unreachable here and omitted.
   Messages are bare (ADR-017), and errors stay in memory (ADR-017). Because `refusePop`
   ends through `forceEnd()`, a refused pop yields exactly **one** error, which keeps
   `Engine_TypeCheckedPopTests` (`currentErrors == [refusal.error]`) valid.
6. **Save wire (amends ADR-018).**
   - `outputStream` keeps its wire: a `[String]` of the text and newline items, in order,
     with tag items left out.
   - `currentTags` keeps its meaning: the tags of the last returned line.
   - **New optional key `outputStreamTags`**: an array of `{"at": Int, "text": String}`.
     - `at` is the index into the saved `outputStream` array **before which** the tag sat:
       `0...outputStream.count`, where `count` means after the last item.
     - Several tags at the same `at` keep their array order.
     - On restore, the tags are put back between the string items at those positions. A tag
       at or before the index of a `"\n"` belongs to the line that newline ends; a tag after
       it belongs to the next line.
     - The key is written only when non-empty. An absent key (old saves, or nothing pending)
       decodes as no lookahead tags.
     - Older builds ignore the key and lose at most the pending lookahead tags.

   There is no version field.

The diagnosis in step 5 is a pure function of (stop reason, return-stack top, choices empty,
safe exit). Applying it is a bounded change to {errors}.

## Alternatives Considered

- **A2 — full `ContinueInternal` alignment** (snapshot at a newline, step until the output
  extends beyond it, then rewind).
  - It would retire the four `mayFlushLine` heuristics and rewind lookahead side effects.
  - **Deferred** to its own feature, with a spike first, opened only if the glue backlog
    proves loop-shaped.
- **A3 — local patches** (a parallel `(outputIndex, tag)` list). **Rejected**: the indices go
  stale whenever glue (`TreeWalker.swift:223-226`) or `nop` (`:228-240`) removes stream items.
- **Clear `currentTags` on every `continue()` only.** **Rejected**: it loses a tag collected
  during lookahead.
- **Persist the stop reason** in a new key. **Rejected**: errors are not saved (ADR-017), so a
  restored state has nothing to diagnose. The prologue resets the reason on the next
  `continue()` anyway.

## Consequences

**Positive**
- #30 and #28 are closed.
- `-> END` discards pending choices, as C# does.
- One end path (`forceEnd()`) for `end` and every runtime error.

**Negative (release-note callouts)**
- A story that runs out of content now reports an error.
- `-> END` now discards pending choices.
- `currentTags` is per-line: a tag no longer stays on later lines.
- Natively compiled stories only match once ADR-021 lands; the two ship together.

**Probes (DISTILL)** — every fixture continues past the construct it pins (CLAUDE.md):
- An untagged line after a tagged one; a line that *starts* with a tag; glue next to a tag.
- Save/restore with a pending lookahead tag; an old save without `outputStreamTags`.
- Each of the three end-of-content messages.
- A refused pop yields exactly one error.
- A choice-continuation root that exhausts without a divert reports "ran out of content".
  Check that **no** well-formed oracle or conformance fixture reaches this path. Any that does
  is investigated before the classification is kept.
- `-> END` with a pending choice.
- The full oracle and conformance suites stay error-free.
