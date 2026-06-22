# Job Analysis — `state-blueprint-compatibility`

**Wave:** DIVERGE · Phase 1 (JTBD) · **Gate G1: PASS**
**Persona:** Maarten — Swift app developer embedding Ink stories

## 1. Raw request (verbatim)

> "I use the compiler and runtime in a game. Where every player has their own story state, but the story blueprint itself is shared. This introduces a coupling between the blueprint (based on the Ink script) and the users story state. If the Ink script changes (knot changes name, variables change, etc) then there's a risk the story state can no longer be restored. Currently, this only appears at runtime when state restoration fails. I'm looking for ways to mitigating this coupling risk."

## 2. Job extraction — 5-Why elevation (tactical → physical)

1. "Restore fails" — **why?** → the save carries no blueprint identity, so a drifted blueprint isn't detected.
2. **why does that hurt?** → the engine silently falls back to root (`navigateAbsolute(...) ?? root`) instead of failing loudly.
3. **why does that matter?** → a live player loses hours of accumulated progress with no warning.
4. **why is that the developer's problem?** → because the developer cannot safely edit a *published* story without risking every outstanding save.
5. **strip to irreducible function (physical):** **preserve a player's accumulated narrative progress as the story it belongs to evolves.**

(≥2 levels of elevation documented; no solution terms in the job statement.)

## 3. Job statements

**Functional (validated):**
> When I have shipped an Ink-driven game whose blueprint I must keep editing while players hold long-lived saves, I want each player's accumulated narrative state to remain restorable against the evolving blueprint — or to be told unambiguously when it cannot be — so I can patch the story without silently corrupting or discarding player progress.

- **Emotional:** feel safe editing a live story; confident that a rename won't quietly break saves.
- **Social:** be seen as a developer who ships a game that respects players' time.

## 4. Disruption check

- "Don't edit published stories" — **rejected**; live games patch by nature.
- "Event-source the playthrough instead of persisting state" — a genuine adjacent job; captured as an *option* (SCAMPER-R, Option F), not a job-killer.

## 5. ODI outcome statements (6)

1. Minimize the **time it takes to** discover a blueprint edit has broken outstanding saves, when preparing a patch.
2. Minimize the **likelihood that** a player's progress is silently degraded (reset to start / wrong location) when restoring against an edited blueprint.
3. Minimize the **likelihood of** a save-breaking change reaching production undetected, when only name-preserving structural edits were made.
4. Minimize the **effort required to** determine which parts of a state survived a restore vs. were dropped, on partial mismatch.
5. Minimize the **time it takes to** carry an existing save across an intentional breaking change (renamed knot), when the mapping is known.
6. Minimize the **likelihood that** a restore failure surfaces to a player rather than the developer first.

## 6. Opportunity candidates (most under-served)

- **O2 + O6** — silent, player-first failure — the most acute pain.
- **O1 / O3** — detect-before-ship — the highest-leverage place to intervene.

## Appendix — Code-grounded failure facts (verified)

- `StoryState` (StoryState.swift:281–410) serializes `variablesState` keyed by **variable name**, `visitCounts` keyed by **dot-joined container-path strings**, `stackFrames[].pathFromRoot` as **arrays of index/name path components**, plus `currentChoices[].targetPath` / `continuationFrames`. **No identity/version field exists** in `CodingKeys`.
- `restoreState` (InkEngine.swift:1075–1083) throws `StoryError.invalidStateData` **only on JSON decode failure** — semantic blueprint drift does not throw.
- Silent degradation confirmed twice: `legacyRestoredContainer()` → `navigateAbsolute(...) ?? root` (1105) and `framesFromSnapshots` → `guard navigateAbsolute(...) else { break }` then `isEmpty ? [root frame]` (1114, 1122).
- `JSONEmitter.emit` (JSONEmitter.swift:23–26) emits `{"inkVersion":21,"root":...}` — the natural injection point for a compile-time content-hash/identity stamp.
