# DISCUSS Decisions — tier3-conditionals-and-tunnels

## Key Decisions

- [D1] Feature type = Backend: all Tier 3 work is internal engine mechanics; no public API changes beyond what is already present on `Story`. Acceptance criteria are expressed entirely through `Story.continue()`, `Story.currentChoices`, and `Story.currentText` observable outputs. (see: brief.md Feature Coverage Matrix rows 22–24, 29–30, 34–35)

- [D2] Tier 3 is split into two independent sub-features by dependency graph: (a) **conditional text and functions** (rows 22–24, 29–30) depend only on the eval stack and existing tree-walker machinery; (b) **tunnels and reference parameters** (rows 34–35) depend on the call-return mechanism already architected in ADR-004. Each sub-feature can ship independently. Slices within each sub-feature follow the order dictated by the The Intercept ceiling: conditional text first (most common idiom), then functions (less frequent but required by The Intercept), then tunnels. (see: brief.md Tier 3 row, ADR-004)

- [D3] Save/restore remains a cross-cutting constraint for all Tier 3 stories, identical to Tier 2. Every behaviour must survive a full `saveState() → restoreState()` round-trip. (see: tier2-choice-mechanics/discuss/wave-decisions.md D3)

- [D4] Reference parameters (`ref x`, row 35) are in scope for Tier 3 because they are required by The Intercept, but they are the lowest-priority slice within the tunnels sub-feature. They depend on function call frames (Slice T2) being implemented first. If time is constrained, row 35 can defer to Tier 4 without blocking The Intercept playthrough — the specific functions using `ref` in The Intercept are known. (see: brief.md row 35 "In The Intercept: Yes")

- [D5] Test fixtures for all Tier 3 slices must be compiled from real Ink source using inklecate at `/Users/maartene/Downloads/inklecate_mac/inklecate`. Hand-crafted JSON is forbidden. This is a hard constraint inherited from project memory and the Tier 2 lessons learned. (see: memory/feedback_real_compiler_json.md, evolution/2026-06-05-tier2-choice-mechanics.md Lesson 1)

- [D6] The feature-id for this tier is `tier3-conditionals-and-tunnels`. Output directory: `docs/feature/tier3-conditionals-and-tunnels/`.

## Requirements Summary

- Primary user need: a story author writing The Intercept (or any story using conditional text, Ink functions, or tunnels) must see correct output from `SwiftInkRuntime` matching the JS-bridge oracle (`InkSwift.InkStory`).
- Walking skeleton scope: not applicable — engine already boots and runs; brownfield feature extension.
- Feature type: backend (engine mechanics).

## Constraints Established

- All story state must remain fully serialisable after every new field; `decodeIfPresent` with safe defaults is required for backward compatibility.
- Test fixtures compiled from real Ink source using inklecate — no hand-crafted JSON.
- No new runtime dependencies.
- macOS-arm64 only; Linux CI deferred (JavaScriptCore transitive dep in `InkSwift` oracle module blocks Linux Docker CI).
- Mutation testing skipped (unreliable for Swift in this project).

## Upstream Changes

None. All features derive directly from documented gaps in `docs/product/architecture/brief.md` Feature Coverage Matrix rows 22–24, 29–30, 34–35. No DISCOVER assumptions changed.
