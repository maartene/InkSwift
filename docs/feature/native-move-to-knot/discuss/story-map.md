# Story Map — native-move-to-knot

## User: Ava — Swift developer building a narrative game using SwiftInkRuntime
## Goal: Programmatically jump to a named knot or stitch in a running Ink story

---

## Backbone

| Resolve Path | Reset Engine State | Install Pointer | Continue from Target | Handle Jump Failure |
|---|---|---|---|---|
| Parse knot + optional stitch into dotted path string | Clear callstack, returnStack, evalStack, currentChoices, outputStream, callFrameVariables, mode flags | Set containerStack to frame pointing at resolved container; set isEnded = false | canContinue == true; first continue() returns target content | Throw StoryError.knotNotFound; do not leave engine in undefined state |
| Validate path exists in container tree | Reset suppressNextNewline | — | Output matches JS-bridge oracle | Error message includes the attempted path |
| Support knot-only and knot+stitch forms | — | — | Save/restore round-trip after jump works | — |

---

## Walking Skeleton

> Note: No walking skeleton is designated because this is a brownfield feature addition. The engine already supports all prerequisite infrastructure (containerStack, returnStack, path resolution). The single deliverable story below IS the minimum working behavior.

**Minimum deliverable**: A developer can call `story.moveToKnot("knotName")` on a running story, the engine resets state and installs the new pointer, `canContinue` is `true`, and `continue()` returns the target knot's first line.

---

## Release 1: Core jump — knot-only, happy path + error path

Stories included:
- US-01: `moveToKnot` with knot name — happy path
- US-02: `moveToKnot` with knot name — error path (knotNotFound)

Outcome KPI targeted: Swift developers can redirect story flow to a named knot without reloading the story.

Rationale: This is the primary use case. Stitch support and save/restore are additive. Error handling must ship with the happy path — a missing error case blocks adoption (developers cannot safely call the API without knowing what to catch).

---

## Release 2: Stitch support and save/restore invariant

Stories included:
- US-03: `moveToKnot(_:stitch:)` — compound path (knot + stitch)
- US-04: Save/restore after a jump produces identical output

Outcome KPI targeted: Full API parity with JS-bridge `moveToKnitStitch(_:stitch:)`; save/restore invariant maintained after jump.

Rationale: Stitch support completes the API signature. Save/restore is a system-wide invariant that every new feature must satisfy; it cannot be deferred to a later release without leaving the invariant unguarded.

---

## Priority Rationale

1. US-01 + US-02 (Release 1) are shipped together — you cannot ship a throwing API without defining what it throws.
2. US-03 (stitch support) is a small incremental addition on top of Release 1; it completes the API surface advertised in the feature request.
3. US-04 (save/restore) validates the system invariant. It has no user-visible behavior but blocks any production use.

Priority order: US-01 > US-02 > US-03 > US-04

---

## Scope Assessment

PASS — 4 stories, 1 bounded context (SwiftInkRuntime engine), estimated 2 days effort.
This is a focused API addition to an existing, well-understood engine. No new source files required; changes are localised to `InkEngine.swift`, `Story.swift`, and `StoryError` (one new case).
