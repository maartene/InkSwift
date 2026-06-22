# DIVERGE Decisions — `state-blueprint-compatibility`

## Key Decisions
- [D1] **Work framed brownfield-but-not-caged** — most options grounded in the current runtime/compiler/state system; ≥1–2 reach slightly beyond (B addressing redesign, F format/event-source). (user framing, this wave)
- [D2] **Research depth: comprehensive** — 5 real named prior-art systems incl. one non-obvious adjacent (Tolerant Reader). (see: `diverge/competitive-research.md`)
- [D3] **SUPERSEDED by D4** — original: "Recommend A, compose with E." Convergence review found A's loud-fail fires at the same coordinates as the current failure (player, runtime, post-ship) and does not serve outcomes O1/O3/O6.
- [D4] **Recommend two-track: Detect (D) + Remediate (E); A dissolves into D-1 + E.** (revised 2026-06-22 — see `recommendation.md` "Revision note")
  - **D = CI/CD compatibility check (DevOps track):** **D-1** content-hash (MD5) of last-shipped vs new blueprint → warning (cheapest first slice); **D-2** structure-relevant diff → reports only save-breaking changes (renamed knots, removed/changed variables).
  - **E = tolerant runtime restore (DELIVER track):** `RestoreResult { restored, dropped, location }` replaces the silent `?? root`.
  - **A's hash relocates to D-1** (player-runtime → CI/developer — the timing/audience move A alone couldn't make); **A's anti-silent intent satisfied by E**. A no longer ships standalone.
  - **Prerequisite:** prior shipped blueprint available at build time (D-1: previous hash; D-2: previous structural fingerprint).

## Job Summary
- **Validated job (`job-state-durability`):** preserve a player's accumulated narrative progress as the shared story blueprint evolves — or report unambiguously when it cannot be restored.
- Abstraction level: physical/strategic (5-Why elevation documented).
- ODI outcomes: 6 statements; most under-served = O2 + O6 (silent, player-first failure) and O1/O3 (detect-before-ship).

## Options Evaluated
- 6 options generated; 6 survived DVF filter (none < 6; F flagged at floor).
- **Raw taste ranking:** A 4.75 > E 4.33 > D 4.18 > B 3.40 > C 2.88 > F 1.83.
- **Recommended direction (post-convergence): two-track Detect (D, as D-1→D-2) + Remediate (E)**, with A dissolved into D-1 + E. The raw matrix under-weighted failure timing/audience; D is the only option that moves the failure to before-ship/developer (serving O1/O3/O6). See `recommendation.md` Revision note.
- **Dissent:** retain a slimmed standalone Option A (restore-time guard) as a runtime floor *only if* CI discipline can't be relied on (bypassed pipeline, third-party-compiled blueprints). Otherwise E's explicit result is the runtime floor.

## Key Risks to carry into DISCUSS
- **D-1 over-triggers by design** — a whole-blueprint hash changes on cosmetic recompiles. Acceptable because D-1 emits a *warning*, not a gate. D-2 (structure-relevant diff) is what reduces the noise.
- **D prerequisite** — the prior shipped blueprint (D-1: previous hash; D-2: previous structural fingerprint) must be stored as a CI input. Confirm where it lives.
- **Runtime floor question** — decide whether E's explicit `RestoreResult` is a sufficient runtime floor, or a standalone A-style restore guard is also required (only if CI can be bypassed).

## SSOT Updates
- `docs/product/jobs.yaml`: bumped `schema_version 1 → 2`, added changelog, appended `job-state-durability` with feature `state-blueprint-compatibility` (status: in DIVERGE wave).

## Self Peer-Review
- Embedded D1–D5 review: **all PASSED → approved**, 1 iteration, no blocking issues. (see: `diverge/review.yaml`)

## Next Wave
- **Handoff to:** nw-product-owner (DISCUSS) via `/nw-discuss`.
- **Deliverable:** `recommendation.md` decision statement — two-track Detect (D-1 → D-2) + Remediate (E), A folded in.
- **Delivery-track split:** D-1/D-2 → DevOps/CI-CD (DEVOPS wave / nw-platform-architect); E → runtime (DELIVER on `SwiftInkRuntime`). Can ship independently; D-1 is the cheapest first slice.
