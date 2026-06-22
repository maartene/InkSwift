# Recommendation — `state-blueprint-compatibility`

**Wave:** DIVERGE → handoff to DISCUSS (nw-product-owner)
**Status:** revised 2026-06-22 after convergence review (see "Revision note" below).
**Derived from:** `diverge/taste-evaluation.md` + `diverge/options-raw.md`, re-weighted for the failure's *timing and audience*, not only its *quality*.

## Revision note — why this differs from the raw taste ranking

The raw taste matrix ranked **A (runtime identity stamp + loud guard)** first. Convergence review found that ranking rewarded developer-tool ergonomics (zero new concepts, fail-fast) while under-weighting the dimension the validated outcomes actually prioritize: **when** the failure fires and **who** sees it.

Two axes were being conflated:

| Axis | Today (silent `?? root`) | Option A alone |
|---|---|---|
| Failure **quality** — silent vs explicit | silent reset | ✅ explicit |
| Failure **timing & audience** — player/runtime/post-ship vs developer/pre-ship | player, runtime, post-ship | ❌ **still** player, runtime, post-ship |

Option A's "fail loud" triggers at `restoreState`, on the player's device, after the broken blueprint shipped — the *same coordinates as the current failure*. It only moves on quality, not on timing/audience. It therefore does **not** serve the two most under-served outcomes:
- **O1** — discover a breaking edit *before* shipping a patch.
- **O3** — stop a save-breaking change reaching production undetected.
- **O6** — keep a restore failure surfacing to the **developer first**, not the player.

A whole-source hash would also *over-trigger* — it changes on cosmetic recompiles, rejecting saves that would have restored fine, which is a net regression versus today's "sometimes still works." A is therefore demoted from lead to a dissolved mechanism (below).

## Recommended direction — two tracks: **Detect (D) + Remediate (E)**

### Track 1 — Detect: build-time compatibility check (Option D), as a DevOps/CI-CD capability

The only option that moves the failure to a different time and audience (developer, pre-ship). Delivered in two increments:

- **D-1 — hash compare (first slice).** A CI step content-hashes (e.g. MD5) the *last-shipped* compiled blueprint against the *new* build and **emits a warning** when it changed. Coarse — trips on any edit, cosmetic or not — but it is a warning, not a gate, so over-triggering is acceptable. Ships value immediately: "the blueprint changed since the last release; outstanding saves may be affected — review before shipping."
- **D-2 — structure-relevant compare (follow-on).** Diffs only the surface saves depend on (knot/container layout, variable names) and reports just the save-breaking changes — e.g. "knot `intro` renamed → `prologue`; variable `trust` removed." Same mechanism family as D-1, better signal-to-noise.

Both D-1 and D-2 are **pure detection** — they tell the developer, they do not preserve any player's progress.

### Track 2 — Remediate: tolerant restore (Option E), a runtime capability

`restoreState` returns an explicit `RestoreResult { restored, dropped, location }` — salvage what is still valid, report what was dropped — replacing the silent `?? root` fallback. This is the only option that keeps a player playing, and the backstop for saves already in the wild when a break ships (including when a developer ships past a D-1 warning anyway).

### What happens to Option A

**A dissolves into D-1 + E** rather than shipping as a standalone option:
- A's **hash mechanism** relocates from the player's device (restore time) to CI (build time) → that *is* **D-1**, and the relocation is exactly the timing/audience move A alone could not make.
- A's **"stop being silent"** intent is satisfied at runtime by **E**'s explicit result.

## Division of labour

- **D = "know before you ship."** Detect at CI, then decide: gate the change, author a migration, or accept the loss.
- **E = "survive what already shipped."** Runtime backstop for saves in the wild.

D and E are complementary and can ship independently, in either order. **D-1 is the cheapest first slice.**

## Prerequisite for D

The prior shipped blueprint must be available at build time:
- **D-1** needs only the *previous content hash* stored (a string in repo / release metadata — tiny).
- **D-2** needs the *previous structural fingerprint* (or the prior `.ink.json` itself).

## Delivery-track / wave split

- **D-1, D-2** → **DevOps / CI-CD pipeline** capability (routes to DEVOPS wave / nw-platform-architect).
- **E** → **runtime** capability (DELIVER on `SwiftInkRuntime`, extending `restoreState`).

## Dissenting case

If the team judges that a *runtime* correctness floor must exist independently of CI discipline (e.g. CI can be bypassed, or third parties compile blueprints outside the team's pipeline), then a slimmed Option A — the restore-time identity check — should be retained as an explicit runtime guard rather than fully folded into E. The margin is narrow because E already converts the silent failure into an explicit, handleable result at runtime; A would add up-front rejection on top of E's salvage. Decide in DISCUSS whether E's explicit result is a sufficient runtime floor or whether a hard A-style guard is also wanted.

## Decision statement for DISCUSS

> **Proceed with a two-track direction: a CI/CD compatibility check (Option D, delivered D-1 hash-warning first, then D-2 structure-relevant report) for detect-before-ship, plus a tolerant restore result (Option E) for runtime remediation — folding Option A's identity-hash into D-1 and its anti-silent intent into E. Assumes the prior shipped blueprint (hash for D-1, structural fingerprint for D-2) can be stored as a CI input, and that E's explicit `RestoreResult` is an acceptable runtime floor (revisit a standalone A-style guard only if CI cannot be relied on).**

First thing DISCUSS should settle: whether E's runtime result is a sufficient floor, or a hard A-style restore guard is also required.
