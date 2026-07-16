# Slice 04 — Honest supported-parity / known-gaps statement (living backlog)

**Feature**: native-runtime-migration
**Story**: US-04
**Job**: job-runtime-consolidation
**Size**: ≤ 1 day
**Role**: "Judge the gaps & decide" — the honesty foundation every other slice
references (README "stay on the bridge if…", migration-guide caveats, deprecation tone).
(Delivery priority **P1 — ships first**; riskiest *content* assumption.)

## Learning hypothesis

> An honest, single-source gaps statement — construct gaps referenced from
> `ink-feature-reference.md`, API gaps stated alongside, and maintained as a living
> backlog — lets an existing consumer correctly self-select migrate vs stay against
> their story's actual features, and trusts it *because it never claims "full parity"*.

If false (the list is incomplete, or over-claims), a consumer migrates and ships a broken
story — the trust failure the "encourage, gaps documented" tone exists to prevent.

## In scope

- `docs/reference/js-bridge-vs-native-parity.md`: recommends `SwiftInkRuntime`, lists the
  known gaps, advises staying on the JS-bridge for them, no "full parity" claim.
- **Feature (construct) gaps reference `docs/product/ink-feature-reference.md`** (the
  construct SSOT — MUST-REJECT rows: LIST, RANDOM/SEED_RANDOM, threads, EXTERNAL, shuffle
  `{~a|b}`) rather than duplicating them.
- **API gaps** stated here (this doc owns them): Combine reactive observation (no native
  equivalent), tag shape (`[String:String]`→`[String]`), error handling (`currentErrors`
  vs native `throws`).
- The **living-parity-backlog** maintenance convention: each later gap-closing feature
  prunes the closed item at its finalize/GREEN step; names the v3.0.0 endpoint.

## Out of scope

- CLOSING any gap (adding LIST/RANDOM/Combine to native) — each is its own future feature.
- Duplicating the construct list (it references the SSOT).
- Any code change.

## Real-consumer data (not synthetic)

- A `LIST` + `RANDOM` + shuffle `{~a|b}` story (Nadia) → must be told to stay.
- A Combine-variable-observation consumer → must be told there is no native equivalent.
- A supported-only, no-Combine story → finds nothing listed → migrates with confidence.
- The maintenance note already at the top of `ink-feature-reference.md`'s "Known gaps /
  future work" section, restated here for the API gaps this doc owns.

## Dogfood moment

Cross-check the construct gaps against `ink-feature-reference.md` MUST-REJECT rows (no
duplication, no divergence) and confirm a `LIST`+Combine consumer reading only this
statement correctly decides to stay on the bridge.

## Taste tests

- **Thin?** Yes — one reference doc aggregating two gap sources.
- **End-to-end?** Yes — a consumer reads it and reaches a stay/migrate/wait decision.
- **User-visible?** Yes — the rendered gaps list + guidance in `docs/reference/`.
- **Independent value?** Yes — the honesty foundation; the whole nudge depends on it.

## Acceptance criteria

See US-04 in `../feature-delta.md`. Green = honest statement (no "full parity"), construct
gaps referenced from the SSOT, API gaps stated, living-backlog convention documented,
v3.0.0 named.
