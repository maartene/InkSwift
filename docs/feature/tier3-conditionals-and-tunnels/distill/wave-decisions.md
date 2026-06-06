# DISTILL Decisions — tier3-conditionals-and-tunnels

**Wave**: DISTILL  
**Designer**: nw-acceptance-designer  
**Date**: 2026-06-05  
**Branch**: native-runtime

---

## Key Decisions

### DWD-01 — Walking Skeleton Strategy: Strategy C (Real local)

**Decision**: Strategy C — all adapters use real implementations; no fakes or in-memory doubles.

**Rationale**: All resources are local filesystem adapters (inklecate-compiled JSON fixtures
embedded in the test bundle). No costly external dependencies. This is a brownfield feature
extension — the engine already boots (Tier 1) and handles choice mechanics (Tier 2). The
story map confirms "walking skeleton not applicable" — the existing `WalkingSkeletonTests`
remains the walking skeleton for the module.

**Tagging**: All new scenarios use `@real-io`. No `@in-memory` doubles.

---

### DWD-02 — Two-Mode Testing Required for Every Slice

**Decision**: Every slice must have tests in both modes:
1. **In-memory**: single `Story` instance played continuously to the assertion point.
2. **Save/restore (rebuild each time)**: state saved and restored into a fresh `Story` instance
   before each action — implementing the "rebuilding the story each time" pattern.

**Rationale**: The user requirement explicitly states: "acceptance tests should cover both
continuing within a story instance as a story save state / restore state (rebuilding the
story each time) cases." Each new StoryState field introduced in Tier 3 (e.g.,
`callFrameVariables` for T3) must survive `saveState()` → `restoreState()` into a fresh
`Story` instance.

---

### DWD-03 — Oracle Comparison Required for Every Slice

**Decision**: Each slice must include at least one oracle comparison test (macOS only) that
drives both `Story` (native) and `InkStory` (JS bridge) from the same inklecate-compiled
fixture and asserts output equality.

**Rationale**: The JS bridge is the ground-truth oracle. The brief states: "The `InkStory`
(JS bridge) serves as a continuously-exercised oracle. Integration tests drive both
implementations against the same `.ink.json` fixture and assert output equality line by line."

---

### DWD-03b — Oracle Test Behavior During RED Phase

**Observation from RED verification**: When oracle tests were run against the unimplemented
engine (all Tier 3 features missing), the following pattern was observed:
- C1 and C2 oracle tests correctly FAIL (RED) — native produces wrong text, mismatch detected.
- T1, T2, T3 oracle tests pass "accidentally" — both native and oracle produce the same empty
  or truncated output when an unimplemented opcode silences the output stream. The assertion
  `nativeLines == oracleLines` holds because both sides produce `[]`.
- The Intercept full oracle playthrough passes "accidentally" — story exits early before
  hitting Tier 3 constructs on the "always pick choice 0" path.

**Implication for DELIVER**: Once partial implementation begins (e.g., C3 `"out"` handler
added but `{"f()": path}` not yet wired), the T1/T2/T3 oracle tests may transition from
false-GREEN to correct-RED. The slice-specific in-memory and save/restore tests are the
PRIMARY RED indicators — they remain RED for the right reasons regardless of this phenomenon.

---

### DWD-04 — The Intercept Full Playthrough as Tier 3 Ceiling Proof

**Decision**: A dedicated suite `TheInterceptAcceptanceTests` contains three tests:
1. Smoke test: TheIntercept.ink.json loads and `canContinue` is true.
2. Save/restore invariant test (15 steps): first 15 output lines match between in-memory
   and save/restore play. Independent of Tier 3 features — should be GREEN early.
3. Full oracle playthrough (macOS only): drives both native and oracle through the story
   picking choice index 0 for determinism (2000 step safety limit); asserts every output
   line matches the oracle. This test is GREEN only when all Tier 3 slices pass.

**Rationale**: The user requirement: "The intent of this tier is that we have enough features
to fully play 'The Intercept' example story. An acceptance test that verifies this would be
very valuable."

**Test file**: `Tests/SwiftInkRuntimeTests/Acceptance/Milestone5_Tier3ConditionalsAndTunnelsTests.swift`

---

### DWD-05 — Fixtures Compiled with Inklecate (No Hand-Crafted JSON)

**Decision**: All new test fixtures were compiled from real Ink source files using inklecate
at `/Users/maartene/Downloads/inklecate_mac/inklecate`. No hand-crafted JSON is used.

**New fixtures added**:
| Source | Compiled JSON | Tests in |
|--------|--------------|---------|
| `slice-c1-inline-conditionals.ink` | `slice-c1-inline-conditionals.ink.json` | C1 suite |
| `slice-c2-block-conditionals.ink` | `slice-c2-block-conditionals.ink.json` | C2 suite |
| `slice-c3-functions.ink` | `slice-c3-functions.ink.json` | C3 suite |
| `slice-t1-tunnels.ink` | `slice-t1-tunnels.ink.json` | T1 suite |
| `slice-t2-nested-tunnels.ink` | `slice-t2-nested-tunnels.ink.json` | T2 suite |
| `slice-t3-ref-params.ink` | `slice-t3-ref-params.ink.json` | T3 suite |
| (from InkSwiftTests/TheIntercept.ink) | `TheIntercept.ink.json` | Intercept suite |

All `.ink.json` files added to `SwiftInkRuntimeTests` resources in `Package.swift`.
All `.ink` source files added to the `exclude` list.

---

### DWD-07 — Non-Trivial Intercept Playthrough Acceptance Test (Addendum, 2026-06-06)

**Decision**: Add a follow-on acceptance test
(`TheInterceptNonTrivialPlaythroughTests`) that drives the engine through a
deterministic, NON-trivial choice script and asserts the first 100 output
lines match a committed JS-bridge oracle fixture line-for-line.

**Rationale**: The original DWD-04 ceiling-proof test (`The Intercept full
playthrough output matches JavaScript oracle`) always picks choice index 0.
On The Intercept that path repeatedly selects "Think" inside the opening
choice cluster and never exercises the Plan / Wait branches that call the
`lower(ref forceful)` and `raise(ref evasive)` functions (C3 + T3). The
ceiling-proof passed without actually proving the C3 / T3 mechanisms
function in a real story context — only the slice fixtures cover them.

A non-trivial choice script (committed in source as
`interceptChoiceScript`) is replayable on both engines, so the test is
reproducible without any hidden state. The choice cursor is `script[i] %
currentChoices.count` so the script remains valid even if a future engine
change alters the visible choice count at some step.

**Test architecture**:
1. `interceptChoiceScript: [Int]` constant — committed in test source.
2. Committed fixture `TheIntercept_oracle_walkthrough.json` — `{choiceScript,
   maxOutputLines, expectedLines}` captured once by driving `InkSwift.InkStory`.
3. Assertion test — drives `Story` through the same script; asserts each
   captured line equals the fixture's `expectedLines[i]`.
4. Regeneration test — gated on `REGEN_INTERCEPT_ORACLE=1`; uses `#filePath`
   to write the fixture into the test source tree. No-op under normal
   `swift test` runs; never affects CI.

**Test file**:
`Tests/SwiftInkRuntimeTests/Acceptance/Milestone5b_TheInterceptNonTrivialPlaythroughTests.swift`

**Fixture**:
`Tests/SwiftInkRuntimeTests/TheIntercept_oracle_walkthrough.json` (added to
`SwiftInkRuntimeTests` resources in `Package.swift`).

**Current state**: **RED**. Diagnosis was corrected on a second pass.
Lines 0-10 match the oracle line-for-line; the first divergence is at
index 11 (NOT index 67 as initially reported), immediately after picking
`* {tellme} [Deny] -> pushes_cup` in the `waited` knot. The native engine
re-enters the depth-2 choice cluster after emitting the labeled-gather
body instead of advancing past it, producing 69 line mismatches downstream
as the engine then follows a different scene through different
`teacup`/`forceful` state. See `distill/upstream-issues.md` Issue 5 (which
has also been corrected) for the full divergence detail and the failed
reproducer attempts. A focused follow-on bugfix feature is needed —
engine-level state instrumentation is required to root-cause it.

---

### DWD-06 — Upstream Issues Documented for Crafter

**Decision**: Fixture inspection revealed four gaps between DESIGN documents and actual
inklecate output. These are documented in `distill/upstream-issues.md` and must be read
by the crafter before implementing each slice.

| Issue | Affects | Gap |
|-------|---------|-----|
| `"out"` control command | C3, T3 | Not in DESIGN; pops evalStack → output; suppresses void |
| `"pop"` control command | T3 | Not in DESIGN; pops evalStack → discard |
| `ci == -1` for globals in `{"^var":}` | T3 | DESIGN assumed `ci == 0` |
| Void functions end at `null` (no `"~ret"`) | C3 | Only `~ret` described in DESIGN |

---

## Self-Review Checklist

- [x] 1. WS strategy declared (DWD-01: Strategy C)
- [x] 2. WS scenarios tagged `@real-io`
- [x] 3. No driven adapters without real-io scenarios (only Bundle/Story adapters; all covered)
- [x] 4. No InMemory doubles used — not applicable
- [x] 5. Container preference: no containers — real files on host
- [x] 6. Mandate 7 (scaffolding): N/A — Swift project; tests compile against existing production
       code (no new public API); tests will fail (RED) at assertion level, not import level
- [x] 7-9. Swift scaffold concept: all tests compile and will fail (RED) because Tier 3 features
       are not yet wired; story continues with wrong/missing output until implemented
- [x] 10. Driving adapter: `Story.init(json:)` is the driving port; all tests enter via it
- [x] 11. F-001: all scenarios exercise real fixtures from Bundle.module
- [x] 12-15. F-002–F-005: not applicable (Swift Testing, not pytest-bdd)
