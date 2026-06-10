# Definition of Ready Validation: story-testability

**Wave**: DISCUSS  
**Date**: 2026-06-10  
**Validator**: Luna (nw-product-owner)

---

## Definition of Ready Validation

### Story: US-01 — Read a Story Variable (getVariable)

| DoR Item | Status | Evidence |
|----------|--------|----------|
| Problem statement clear, domain language | PASS | "Raya cannot read VAR values from a running story without internal access to StoryState.variablesState" — domain language, concrete pain |
| User/persona with specific characteristics | PASS | Raya — Swift developer and Ink story author, writing Swift Testing suites, needs direct variable read access |
| 3+ domain examples with real data | PASS | 3 examples: integer score=42, boolean badge_awarded=true, unknown variable "ghost_var" → nil |
| UAT in Given/When/Then (3-7 scenarios) | PASS | 4 scenarios: integer read, boolean read, unknown variable nil, string read |
| AC derived from UAT | PASS | 5 AC items, each traceable to a scenario |
| Right-sized (1-3 days, 3-7 scenarios) | PASS | 0.5 days, 4 scenarios |
| Technical notes: constraints/dependencies | PASS | InkValue bridging, variablePointer → nil, no new StoryState fields |
| Dependencies resolved or tracked | PASS | Depends only on existing InkEngine.state.variablesState (internal, accessible via @testable) |
| Outcome KPIs defined with measurable targets | PASS | KPI-1: ≥1 variable-assertion test per branching knot; baseline 0 |

### DoR Status: PASSED

---

### Story: US-02 — Write a Story Variable (setVariable)

| DoR Item | Status | Evidence |
|----------|--------|----------|
| Problem statement clear, domain language | PASS | "Replaying fragile choice sequence breaks when story adds a choice; chooseChoice(at: 2) becomes chooseChoice(at: 3)" — concrete, domain-language pain |
| User/persona with specific characteristics | PASS | Raya — Swift developer / Ink story author writing unit tests for story conditional logic |
| 3+ domain examples with real data | PASS | 3 examples: integer score=10 triggers gold badge, boolean has_key=true opens door, unknown variable "scroe" is no-op |
| UAT in Given/When/Then (3-7 scenarios) | PASS | 5 scenarios: output change, read-back confirms value, unknown name no-throw, boolean injection, string injection |
| AC derived from UAT | PASS | 5 AC items, each traceable to a scenario |
| Right-sized (1-3 days, 3-7 scenarios) | PASS | 0.5 days, 5 scenarios |
| Technical notes: constraints/dependencies | PASS | InkValue bridging (reverse direction), unknown name open question flagged for DESIGN, production use case noted |
| Dependencies resolved or tracked | PASS | Depends on US-01 type bridging strategy being established first; sequenced in slice order |
| Outcome KPIs defined with measurable targets | PASS | KPI-1 (adoption), KPI-4 (refactoring survivability); baseline 0 |

### DoR Status: PASSED

---

### Story: US-03 — Read and Write Knot Visit Counts (visitCount / setVisitCount)

| DoR Item | Status | Evidence |
|----------|--------|----------|
| Problem statement clear, domain language | PASS | "Stories using {knotName} visit count syntax (Pattern B) cannot be unit-tested with injected state" — domain language, specific Ink pattern cited |
| User/persona with specific characteristics | PASS | Raya — uses both VAR (Pattern A) and {knotName} (Pattern B) in the same story |
| 3+ domain examples with real data | PASS | 3 examples: visit count 2 triggers "Welcome back!", read-back after natural navigation returns 1, unknown knot "chapter_four" returns 0 |
| UAT in Given/When/Then (3-7 scenarios) | PASS | 4 scenarios: set enables branch, read-back confirms, unknown knot returns 0, natural navigation increments |
| AC derived from UAT | PASS | 5 AC items, each traceable to a scenario |
| Right-sized (1-3 days, 3-7 scenarios) | PASS | 0.5 days, 4 scenarios |
| Technical notes: constraints/dependencies | PASS | visitCounts dict key format documented, anonymous containers explicitly excluded, symmetric with setVariable pattern |
| Dependencies resolved or tracked | PASS | Independent of US-01/US-02 — separate state dict; no dependency |
| Outcome KPIs defined with measurable targets | PASS | KPI-2: ≥1 setVisitCount test per visit-count-dependent knot; baseline 0 |

### DoR Status: PASSED

---

### Story: US-04 — Drain All Story Output (continueMaximally)

| DoR Item | Status | Evidence |
|----------|--------|----------|
| Problem statement clear, domain language | PASS | "Four lines of while-loop boilerplate repeated in every WHEN step; manual loop invites off-by-one bugs" — concrete pain, specific line count |
| User/persona with specific characteristics | PASS | Raya — writing the WHEN step of a GWT story test, wants concise readable code matching reference API |
| 3+ domain examples with real data | PASS | 3 examples: multi-line output from "reward_check" knot containing "gold badge", multi-line join, already-ended story returns "" |
| UAT in Given/When/Then (3-7 scenarios) | PASS | 4 scenarios: output contains expected text, equality with manual loop, ended story returns "", stops at choice point |
| AC derived from UAT | PASS | 5 AC items, each traceable to a scenario |
| Right-sized (1-3 days, 3-7 scenarios) | PASS | 0.5 days, 4 scenarios |
| Technical notes: constraints/dependencies | PASS | Pure facade delegation; no engine/state changes; @discardableResult; production use case (headless rendering) noted |
| Dependencies resolved or tracked | PASS | No dependencies — uses only the existing public `continue()` method |
| Outcome KPIs defined with measurable targets | PASS | KPI-3: `while canContinue` boilerplate eliminated from new tests; baseline 0 continueMaximally calls |

### DoR Status: PASSED

---

## Overall DoR Summary

| Story | DoR Status | Blockers |
|---|---|---|
| US-01 getVariable | PASSED | None |
| US-02 setVariable | PASSED | None |
| US-03 visitCount / setVisitCount | PASSED | None |
| US-04 continueMaximally | PASSED | None |

**All 4 stories: PASSED — Ready for DESIGN wave handoff.**

---

## Anti-Pattern Check

| Anti-Pattern | Check | Result |
|---|---|---|
| Implement-X story titles | Story titles start from user pain, not from implementation | PASS — titles describe user capability gained |
| Generic data | Examples use "ghost_var", "ghost_town", "score", "badge_awarded", "prologue" — realistic story domain names | PASS — no user123 or test@test.com |
| Technical AC | AC describes observable user outcomes and API contract | PASS — no "use JWT", no implementation prescriptions |
| Technical scenario titles | Scenario titles describe what story author achieves | PASS — "Setting a variable changes subsequent story output" not "setVariable writes to variablesState dict" |
| Oversized stories | Largest story has 5 scenarios; all are 0.5 days | PASS — well within 3-7 scenario target |
| Abstract requirements | All stories have 3+ domain examples with real values | PASS |

---

## Peer Review Notes

This document serves as the self-review record for the DISCUSS wave. All 4 stories pass the 9-item DoR checklist. The two open questions flagged in `wave-decisions.md` (D-02 unknown variable create-vs-noop, D-08 setVariable signature overloads vs some Any) are appropriately deferred to the DESIGN wave and do not block handoff.
