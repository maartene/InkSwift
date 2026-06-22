# Options (raw) — `state-blueprint-compatibility`

**Wave:** DIVERGE · Phase 3 (Brainstorming) · **Gate G3: PASS** (6 options, 3-point diversity, SCAMPER-E + SCAMPER-R present)

> Generation-only artifact. No scoring or "best" language here — evaluation lives in `taste-evaluation.md`.

## HMW question (no embedded solution)

*How might we let a developer evolve a shipped Ink story without players' saved progress silently breaking?*

## Curated 6 options

### Option A: Blueprint identity stamp + loud restore guard
- **Core idea:** the player's save is checked against the story version it belongs to, and a mismatch is reported instead of silently resetting.
- **Key mechanism:** the compiler embeds a content-hash / version in the JSON header; `saveState` records it; `restoreState` compares and **throws on mismatch** instead of `?? root`.
- **Key assumption:** any blueprint change worth detecting changes the stamp, AND cosmetic/non-semantic recompiles do not.
- **SCAMPER origin:** M (Modify/Magnify — magnify the missing identity dimension).
- **Closest competitor:** ink's `kInkSaveStateVersion` (but content-aware, not format-only).

### Option B: Name-stable addressing
- **Core idea:** saves keep working after structural edits as long as knot/variable names are unchanged.
- **Key mechanism:** serialize visit/stack state against stable **named anchors** (knot/var names) instead of positional container-index paths.
- **Key assumption:** authors preserve names across edits more reliably than they preserve structure.
- **SCAMPER origin:** S (Substitute — replace the path mechanism).
- **Closest competitor:** Protobuf field-numbers (identity decoupled from layout).

### Option C: Versioned save + migration chain
- **Core idea:** the developer ships ordered migrations that carry old saves forward across intentional breaking changes.
- **Key mechanism:** a `saveVersion` field; developer (or codegen) authors ordered up-migrations between blueprint versions, applied on restore.
- **Key assumption:** breaking changes are intentional and the developer will author a migrator for each.
- **SCAMPER origin:** C (Combine — merge with the DB-migration job).
- **Closest competitor:** Flyway / Unity game-save chains.

### Option D: Build-time compatibility report
- **Core idea:** before shipping, the developer is told which of their edits will break outstanding saves.
- **Key mechanism:** a compiler/tool **diffs two blueprint versions** and classifies each change save-compatible vs save-breaking — no runtime change.
- **Key assumption:** both blueprint versions are available at build time (e.g. in CI).
- **SCAMPER origin:** A (Adapt — borrow API-diff / `buf breaking` tooling).
- **Closest competitor:** `buf breaking` / API-diff linters.

### Option E: Tolerant best-effort restore with explicit result
- **Core idea:** restore recovers everything it can and hands back a report of what survived and what was dropped, instead of all-or-nothing or silent corruption.
- **Key mechanism:** `restoreState` returns a `RestoreResult { restored, dropped, location }`; drops only the unresolvable parts and reports them.
- **Key assumption:** partial progress is more valuable than strict rejection, provided the gaps are reported.
- **SCAMPER origin:** **E (Eliminate — remove the all-or-nothing / silent failure).**
- **Closest competitor:** Tolerant Reader / Postel's robustness principle.

### Option F: Event-sourced playthrough (decouple from layout)
- **Core idea:** persist the player's choices/seed log, then replay it against the current blueprint to reconstruct state.
- **Key mechanism:** store inputs (choices, RNG seed) rather than positional state; reconstruct by replay on load.
- **Key assumption:** a playthrough is deterministically replayable against an edited blueprint.
- **SCAMPER origin:** **R (Reverse — store inputs, derive state).** *(Slightly-beyond-scope: format redesign.)*
- **Closest competitor:** event-sourcing / replay-based save systems.

## Diversity test (3-point: mechanism / assumption / cost)

Every pair differs in ≥2 of {mechanism, user-behavior assumption, cost locus}:

| Opt | Mechanism | Assumption about *how/how-often* the script changes | Cost locus |
|---|---|---|---|
| A | identity check at restore boundary | any change | compiler + runtime, small |
| B | change the save's addressing scheme | name-preserving edits | runtime save/restore + paths, **large** |
| C | ordered migrators | intentional breaks | author + runtime runner, medium-large |
| D | static pre-ship diff | intentional breaks | compiler/tooling only, medium |
| E | best-effort partial + report | any, salvage | runtime only, small-medium |
| F | reconstruct by replay | any, replayable | runtime + format redesign, **large** |

No two options share all three → **no merges**. Required coverage present: **E = radical simplification**, **F = inversion**.

## Eliminated / merged

None merged — all six survived the diversity test as distinct approaches. Crazy-8s supplements that collapsed into existing options (e.g. "warn-only banner" → a softer variant of A; "snapshot full blueprint into the save" → an expensive variant of A's identity idea) were dropped in favour of their stronger representatives.
