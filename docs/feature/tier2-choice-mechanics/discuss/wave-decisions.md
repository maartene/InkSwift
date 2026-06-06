# DISCUSS Decisions — tier2-choice-mechanics

## Key Decisions

- [D1] Feature type = Backend: these are engine-internal mechanics with no UI surface. All stories are expressed in terms of `Story` API outputs observable by a developer host app. (see: brief.md Feature Coverage Matrix rows 8–11, 14)
- [D2] Priority order is once-only suppression first, then conditional gating, then read counts, then invisible defaults: the Cass story breaks at once-only (highest user-visible pain); conditional gating is close to done (parsing exists); read counts need once-only counts to be reliable first; invisible defaults are a correctness edge case with no known breaking story. (see: story-map.md Prioritization Rationale)
- [D3] Save/restore as cross-cutting constraint: the consumer pattern (InkTest creates a fresh `Story` every iteration and calls `restoreState`) means `blueprint + state` must fully describe every feature's effect. Acceptance criteria for every story include a save/restore variant. (see: user-stories.md Cross-cutting Acceptance Criterion)
- [D4] Slices 01+02+03+04 are delivered in dependency order, not by priority alone: Slice 03 needs reliable visitCounts (Slice 01 prerequisite); Slice 04 needs once-only exhaustion to be reachable (Slice 01 prerequisite). (see: story-map.md Slices)
- [D5] A single tracking mechanism serves both visit-count logic and once-only suppression: the Ink language uses the same "has this location been entered?" concept for both. The implementation detail of how this is stored is deferred to DESIGN. (see: user-stories.md Story 3 AC1)

## Requirements Summary

- Primary user need: a story author's Ink source code behaviour (once-only choices disappear, conditionals gate, visit counts accumulate) must be faithfully reproduced by the Swift engine.
- Walking skeleton scope: not applicable (engine already boots; Tier 1 complete).
- Feature type: backend (engine mechanics).

## Constraints Established

- All story state must be fully serialisable; save/restore is a first-class requirement, not an afterthought.
- Test fixtures must be compiled from real Ink source using inklecate; authored-by-hand JSON is not acceptable.
- No new runtime dependencies are to be introduced.

## Upstream Changes

None. All features derive directly from documented gaps in `brief.md` Feature Coverage Matrix. No DISCOVER assumptions changed.
