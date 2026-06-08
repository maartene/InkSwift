# Definition of Ready Validation — native-move-to-knot

Date: 2026-06-08
Reviewer: Luna (nw-product-owner, review mode)
Artifact: docs/feature/native-move-to-knot/discuss/user-stories.md

---

## Story US-01 — Jump to a Named Knot (Happy Path)

| DoR Item | Status | Evidence |
|---|---|---|
| Problem statement clear, domain language | PASS | "She finds it impossible to redirect a running Story to a specific knot: the only way is to reload the entire story from JSON and manually advance through chapters" |
| User/persona identified with specific characteristics | PASS | "Ava — Swift developer building a narrative game, mid-execution, wants chapter-select / debug jump / scene-replay" |
| 3+ domain examples with real data | PASS | 3 examples: TheIntercept fixture + named knots ("interrogation", "prologue", "epilogue"); real fixture path referenced |
| UAT scenarios in Given/When/Then (3-7) | PASS | 5 scenarios; all in Given/When/Then form; scenario titles describe business outcomes |
| AC derived from UAT | PASS | 8 AC items; each maps to observable behaviour from a scenario |
| Right-sized (1-3 days, 3-7 scenarios) | PASS | 1 day effort estimate; 5 scenarios; single demonstrable behavior |
| Technical notes identify constraints | PASS | Signature, new StoryError case, state reset field list, dependency chain all specified |
| Dependencies resolved or tracked | PASS | "Dependency: none. Independent of all Tier 1–3 stories." |
| Outcome KPIs defined | PASS | KPI #1 in outcome-kpis.md: 100% oracle match; measured by XCTAssertEqual |

### DoR Status: PASSED

---

## Story US-02 — Jump Throws knotNotFound for Non-Existent Knot

| DoR Item | Status | Evidence |
|---|---|---|
| Problem statement clear, domain language | PASS | "If a config entry contains a typo or refers to a knot that was renamed in a later Ink revision, the engine must tell her immediately" |
| User/persona identified | PASS | "Ava — Swift developer, implementing a chapter-select UI backed by config-driven knot names" |
| 3+ domain examples with real data | PASS | 3 examples: typo "interrogaton", renamed "lab"→"laboratory", empty string |
| UAT scenarios (3-7) | PASS | 4 scenarios; all in Given/When/Then; titles describe observable error outcomes |
| AC derived from UAT | PASS | 6 AC items covering knotNotFound case, compound path, empty string, no-mutation-before-throw, Equatable |
| Right-sized | PASS | 0.5 day effort; 4 scenarios; error branch of US-01 method |
| Technical notes | PASS | Throw-before-mutate ordering constraint documented |
| Dependencies resolved | PASS | "Dependency: US-01 must be in progress (same method, error branch)" |
| Outcome KPIs defined | PASS | KPI #2 in outcome-kpis.md: 100% knotNotFound thrown |

### DoR Status: PASSED

---

## Story US-03 — Jump to a Knot + Stitch

| DoR Item | Status | Evidence |
|---|---|---|
| Problem statement clear, domain language | PASS | "calling moveToKnot('investigation') takes her to the knot's root, not the lab stitch she wants" |
| User/persona identified | PASS | "Ava — Swift developer authoring a story with stitches inside knots" |
| 3+ domain examples with real data | PASS | 3 examples: TheIntercept investigation.lab, nil stitch = knot root, non-existent stitch "dungeon" |
| UAT scenarios (3-7) | PASS | 4 scenarios covering happy path, nil stitch, oracle match, and error |
| AC derived from UAT | PASS | 5 AC items directly mapped from scenarios |
| Right-sized | PASS | 0.5 day; 4 scenarios; additive to US-01 path resolution |
| Technical notes | PASS | Path construction formula documented; resolution approach specified |
| Dependencies resolved | PASS | "Dependency: US-01 (the core jump mechanism)" |
| Outcome KPIs defined | PASS | KPI #1 extended to include compound-path jumps |

### DoR Status: PASSED

---

## Story US-04 — Save/Restore Round-Trip After a Jump

| DoR Item | Status | Evidence |
|---|---|---|
| Problem statement clear, domain language | PASS | "If save/restore is broken after a jump, auto-saving immediately after chapter-select corrupts the save file" |
| User/persona identified | PASS | "Ava — Swift developer, game has an auto-save system" |
| 3+ domain examples with real data | PASS | 3 examples: save after jump + restore, pre-jump save unaffected, save after second jump |
| UAT scenarios (3-7) | PASS | 3 scenarios; all Given/When/Then; titles describe correctness of save/restore behavior |
| AC derived from UAT | PASS | 5 AC items covering post-jump position, pre-jump isolation, compound path, stale-frame absence |
| Right-sized | PASS | 0.5 day; 3 scenarios; no new logic required — validation of existing Codable machinery |
| Technical notes | PASS | No new save/restore logic; stackFrames snapshot invariant identified; dependency on US-01 noted |
| Dependencies resolved | PASS | "Dependency: US-01 (core jump) must ship first" |
| Outcome KPIs defined | PASS | KPI #3 in outcome-kpis.md: 100% correct location on restore |

### DoR Status: PASSED

---

## Feature-Level DoR Summary

| Story | DoR Status |
|---|---|
| US-01 | PASSED |
| US-02 | PASSED |
| US-03 | PASSED |
| US-04 | PASSED |

**Feature DoR Status: PASSED — all 4 stories ready for DESIGN wave handoff.**

---

## Peer Review

```yaml
review_id: "req_rev_20260608_001"
reviewer: "product-owner (review mode)"
artifact: "docs/feature/native-move-to-knot/discuss/user-stories.md"
iteration: 1

strengths:
  - "Elevator Pitch present on all 4 stories with real entry point (public method signature), concrete output (currentText / thrown error type), and decision enabled (chapter-select, safe catch)"
  - "State reset field list is exhaustive and cross-checked against StoryState.swift — no field left ambiguous"
  - "Explicit separation of preserved fields (variablesState, visitCounts, chosenChoiceTargets) vs. cleared fields prevents a common implementation mistake"
  - "JS-bridge oracle requirement appears in US-01 AC and cross-cutting criterion — testability is concrete"
  - "Domain examples use real fixture names (TheIntercept, interrogation, investigation.lab) not generic placeholders"
  - "Error story (US-02) ships in the same release as the happy-path story (US-01) — no half-baked API"

issues_identified:
  confirmation_bias: []

  completeness_gaps: []

  clarity_issues: []

  testability_concerns: []

  priority_validation:
    q1_largest_bottleneck: "YES — moveToKnot is the last major JS-bridge API method not yet available in SwiftInkRuntime"
    q2_simple_alternatives: "ADEQUATE — reloading the story JSON is the only alternative and is documented as the workaround in Problem statements"
    q3_constraint_prioritization: "CORRECT — error handling (US-02) ships with happy path (US-01); save/restore (US-04) validates system invariant"
    q4_data_justified: "JUSTIFIED — JS-bridge oracle provides a concrete correctness benchmark; 154-test regression guard prevents regressions"
    verdict: "PASS"

approval_status: "approved"
critical_issues_count: 0
high_issues_count: 0
```
