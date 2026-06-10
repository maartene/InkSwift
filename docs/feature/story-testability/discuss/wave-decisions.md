# Wave Decisions: story-testability DISCUSS Wave

**Wave**: DISCUSS  
**Feature**: story-testability  
**Date**: 2026-06-10  
**Author**: Luna (nw-product-owner)

---

## Decisions Made in This Wave

### D-01: JTBD Analysis Skipped

**Decision**: Skip full JTBD/DIVERGE analysis per user instruction.  
**Rationale**: Problem is well-understood from prior conversation; developer persona is clear; four specific API gaps are already identified. JTBD discovery would not surface new information.  
**Risk**: Low — all journey ground truth was provided by the user directly.  
**Note**: No `docs/feature/story-testability/diverge/` artifacts exist. This is logged as a risk per workflow step 1, but assessed as low severity given the specificity of the brief.

---

### D-02: API Error Contract — Silent No-Op for Unknown Names

**Decision**: Unknown variable names and unknown knot names in `setVariable`, `setVisitCount`, `getVariable`, `visitCount` are silent no-ops / return-zero / return-nil — they do not throw.  
**Rationale**: Story authors may reference variables by string; typos should not crash tests. The failure mode is observable (getVariable returns nil; test fails at the #expect level, not the API level). This matches the reference inkjs behaviour.  
**Trade-off**: A typo in a variable name is harder to detect at the API level. Mitigation: the downstream test assertion will fail.  
**Open question for DESIGN wave**: Should `setVariable` for a name not in `variablesState` create a new key (useful for dynamic scripting) or be a pure no-op? Left to DESIGN to decide based on inkjs reference behaviour.

---

### D-03: InkValue Must Not Leak into Public API

**Decision**: `InkValue` enum (internal to `SwiftInkRuntime`) must not appear in any method signature on `Story`.  
**Rationale**: `InkValue` is an implementation detail of the tree-walker engine. Exposing it would couple story authors to internal engine types.  
**Implementation**: `getVariable` returns `Any?` bridging `InkValue` cases to Swift native types. `setVariable` accepts `some Any` or overloaded typed methods (DESIGN choice). `visitCount` returns `Int` directly.

---

### D-04: Visit Count API Scope — Named Knots Only

**Decision**: `visitCount(forKnot:)` and `setVisitCount(forKnot:to:)` accept only named knot name strings. Anonymous container paths (choice arms, gathers) are not exposed.  
**Rationale**: Anonymous container keys are opaque inklecate-internal paths (e.g., `"0.0.3"`). They are not stable across story edits. Exposing them would create a fragile API. Story authors have no access to these keys without inspecting compiled JSON.  
**Scope**: Named knots only — the key is the knot name string as it appears in the `.ink` source.

---

### D-05: continueMaximally Concatenation Strategy

**Decision**: `continueMaximally()` concatenates all `continue()` return values (already whitespace-cleaned) in sequence and returns the result as a single `String`.  
**Rationale**: Matches the reference C# `ContinueMaximally()` return type. Concatenation preserves newlines. Story authors can split by `\n` for line-by-line assertions if needed.  
**Note**: The method stops at a choice point (when `canContinue == false` because choices are available), not only at story end. This matches the C# reference behaviour.

---

### D-06: Slice Sequence

**Decision**: Slices are sequenced 01 → 02 → 03 → 04.  
**Rationale**:
- Slice 01 (getVariable): read-only; validates type bridging strategy with minimal risk before write is added
- Slice 02 (setVariable): write symmetric with get; highest user value (GIVEN injection)
- Slice 03 (visitCounts): independent state dict; can ship in parallel with 01/02 but sequenced for review clarity
- Slice 04 (continueMaximally): pure facade delegation; no state changes; completes the WHEN step

---

### D-07: No New Source Files Required

**Decision**: All four slices extend existing files only (`Facade/Story.swift` and the internal `Engine/InkEngine.swift` for state accessor delegation). No new source files are introduced.  
**Rationale**: Consistent with the project's established EXTEND pattern. The `Story` facade is the single public surface; InkEngine is the single internal state owner.

---

### D-08: moveToKnot as Prerequisite (Not Part of This Feature)

**Decision**: `moveToKnot` already exists on the public API and is not part of this feature's scope. The story-testability feature complements it.  
**Rationale**: `moveToKnot` was delivered as the `native-move-to-knot` feature (archived). Tests for story-testability may use `moveToKnot` in their GIVEN step.

---

## Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| `InkValue` type bridging produces unexpected Swift types | Low | Medium | US-01 Slice 01 validates bridging before setVariable; test fixtures cover all four InkValue types |
| Anonymous container key leak (story author accidentally uses opaque path) | Low | Low | API accepts only String; wrong key returns 0/nil silently — no crash |
| DIVERGE artifacts absent | Low | Low | Problem is well-specified by user; all ground truth provided in session |
| `setVariable` for unknown name: no-op vs create key ambiguity | Medium | Low | Flagged as open question for DESIGN wave (D-02) |

---

## Open Questions for DESIGN Wave

1. **`setVariable` for unknown name**: pure no-op (do not write to `variablesState`) or create key? Recommend DESIGN checks inkjs reference behaviour.
2. **`setVariable` method signature**: single `some Any` parameter vs overloaded per-type methods (`to value: Int`, `to value: Bool`, etc.)? Per-type overloads give better Swift type inference; `some Any` is simpler surface area. DESIGN decision.
3. **`continueMaximally` and `currentErrors`**: if execution produces errors during the drain loop, should `continueMaximally` continue looping or halt and surface errors? Recommend matching `continue()` behaviour (errors accumulate in `currentErrors`, loop does not halt).
