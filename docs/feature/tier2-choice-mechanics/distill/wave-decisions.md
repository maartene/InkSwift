# DISTILL Decisions — tier2-choice-mechanics

## DWD-01: Walking Skeleton Strategy

**Decision**: Strategy C (Real local). All adapters use real implementations. No fakes or in-memory doubles.

**Rationale**: This is a pure-engine feature. The only driven adapter is InkDecoder, which reads `.ink.json` from the test bundle — already working since Tier 1. There are no external services, no costly dependencies, and no need for containerised environments. The Tier 1 walking skeleton is already green; DISTILL adds Tier 2 behavioural scenarios on top.

**Tagging**: All Tier 2 acceptance tests carry `@real-io`. No `@in-memory` scenarios exist.

---

## DWD-02: Test-Mode Variants

**Decision**: Every acceptance criterion is covered in two modes:
1. **In-memory**: a single `Story` instance played continuously to the assertion point.
2. **Save/restore**: state saved after each significant action and restored into a fresh `Story` instance before each subsequent action (the `InkTest` / `SharedWorldYourStory` production pattern, per DISCUSS D3).

The save/restore variant is NOT a separate acceptance criterion — it is a mandatory execution mode for every criterion. A behaviour that passes in-memory but fails save/restore is a regression.

---

## DWD-03: Fixture Compilation

**Decision**: All test fixtures are compiled from real Ink source files using inklecate at:
`/Users/maartene/Downloads/inklecate_mac/inklecate`

Source files and compiled JSON are at:
- `Tests/SwiftInkRuntimeTests/slice01-once-only.ink` → `slice01-once-only.ink.json`
- `Tests/SwiftInkRuntimeTests/slice02-conditional.ink` → `slice02-conditional.ink.json`
- `Tests/SwiftInkRuntimeTests/slice03-read-counts.ink` → `slice03-read-counts.ink.json`
- `Tests/SwiftInkRuntimeTests/slice04-invisible-defaults.ink` → `slice04-invisible-defaults.ink.json`

**Rationale**: Per project feedback, hand-crafted JSON misses numeric path prefixes and produces tests that pass against wrong implementations. Real compiler output is authoritative.

---

## DWD-04: Oracle Use

**Decision**: `InkSwift.InkStory` (JavaScript bridge) is used as an oracle in macOS-only `#if os(macOS)` tests for the most diagnostically valuable assertions:
- Slice 01: once-only suppression (choice set equality after pick)
- Slice 02: conditional gating at story start (boolean presence/absence match)
- Slice 03: visit-count conditional text on second visit (text presence match)

Oracle comparisons are additive — they do NOT replace the primary behavioural assertions. Each oracle test assumes the oracle produces correct output per the Ink specification.

---

## DWD-05: Reconciliation Result

Reconciliation passed — 0 contradictions between DISCUSS and DESIGN wave decisions.

- DISCUSS D1–D5 map directly to DESIGN D1–D6.
- DEVOPS artifacts absent → default environment matrix applied (macOS-arm64 only, per project feedback).
- SPIKE not run for tier2 → no spike findings to reconcile.
