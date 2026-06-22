# Taste Evaluation — `state-blueprint-compatibility`

**Wave:** DIVERGE · Phase 4 · **Gate G4: PASS**

> **Pointer (2026-06-22):** This matrix is the *raw* taste ranking (A first). Convergence review re-weighted for the failure's **timing & audience** — the dimension this Developer-Tool matrix under-scored — and the recommended direction is now **two-track Detect (D, as D-1 → D-2) + Remediate (E)**, with A's hash folded into D-1 and A's anti-silent intent into E. See `../recommendation.md` "Revision note" for the reasoning. The scores below are preserved as the historical generation record.

## Phase 1 — DVF filter (1–5; eliminate if total < 6)

Viability here = long-term maintainability / fit with the product, not revenue.

| Opt | Desirability | Feasibility | Viability | Total | Verdict |
|---|---|---|---|---|---|
| A | 5 | 5 | 5 | 15 | survive |
| B | 4 | 2 | 3 | 9 | survive |
| C | 4 | 3 | 3 | 10 | survive |
| D | 4 | 4 | 4 | 12 | survive |
| E | 5 | 4 | 5 | 14 | survive |
| F | 3 | 2 | 2 | 7 | survive (barely — flagged) |

No eliminations (all ≥ 6). **F** is closest to the floor — large format redesign, replay-determinism risk with RANDOM / external input.

## Phase 2/3 — Locked weights (Developer Tool profile, locked before scoring)

| Criterion | Weight |
|---|---|
| DVF (avg) | 25% |
| T1 Subtraction | 15% |
| T2 Concept Count | 20% |
| T3 Progressive Disclosure | 15% |
| T4 Speed-as-Trust | 25% |

## Scoring matrix (1–5; weighted total max 5.0)

| Opt | DVF(avg) | T1 Subtraction | T2 Concept | T3 Disclosure | T4 Speed-as-Trust | **Weighted** |
|---|---|---|---|---|---|---|
| **A** | 5.0 | 5 | 5 | 5 | 4 | **4.75** |
| **E** | 4.67 | 4 | 4 | 4 | 5 | **4.33** |
| **D** | 4.0 | 4 | 4 | 4 | 5 | **4.18** |
| B | 3.0 | 3 | 3 | 4 | 4 | 3.40 |
| C | 3.33 | 2 | 2 | 3 | 4 | 2.88 |
| F | 2.33 | 2 | 1 | 2 | 2 | 1.83 |

### Per-criterion rubric justification

- **A** — T2=5: zero new concepts ("your save is from a different story version"); T3=5: default behaviour, no opt-in; T4=4: one hash compare at restore, fail-fast *is* trust.
- **E** — T2=4: one new concept (a `RestoreResult`); T4=5: no blocking, instant best-effort.
- **D** — T3=4: a build-time report maps to lint / `buf breaking`; T4=5: build-time, zero runtime latency.
- **B** — T2=3: anchors mostly invisible to the user; T3=4: transparent once shipped.
- **C** — T2=2: a migration chain is a new mental model; T1=2: ceremony per version.
- **F** — T2=1: event-sourcing is a whole new model; T4=2: replay latency on load.

## Ranking

**A 4.75 > E 4.33 > D 4.18 > B 3.40 > C 2.88 > F 1.83.**
