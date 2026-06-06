# Definition of Ready Validation — tier3-conditionals-and-tunnels

Reviewer: Luna (nw-product-owner — review mode)
Date: 2026-06-05
Iteration: 1

---

## Story C1 — Inline Conditional Text

| DoR Item | Status | Evidence |
|---|---|---|
| Problem statement clear, domain language | PASS | "The engine ignores the condition and outputs the wrong branch"; domain terms: `evalStack`, `{c: a\|b}`, `continue()` |
| User/persona with specific characteristics | PASS | Ava — Swift game developer running a narrative game with `SwiftInkRuntime` |
| 3+ domain examples with real data | PASS | `metCass` variable, `score > 5`, named fixture `conditional_inline.ink` |
| UAT in Given/When/Then (3–7 scenarios) | PASS | 5 scenarios; all in Given/When/Then form |
| AC derived from UAT | PASS | 5 AC lines, each traceable to a scenario |
| Right-sized (1–3 days, 3–7 scenarios) | PASS | ~4 hours; 5 scenarios |
| Technical notes: constraints/dependencies | PASS | inklecate JSON encoding note; evalStack re-use from Tier 2; dependency: none |
| Dependencies resolved or tracked | PASS | No blocking dependencies within Tier 3; Tier 1+2 complete |
| Outcome KPIs defined | PASS | KPI 1 in outcome-kpis.md |

### DoR Status: PASSED

---

## Story C2 — Block and Switch Conditionals

| DoR Item | Status | Evidence |
|---|---|---|
| Problem statement clear, domain language | PASS | "Engine does not handle block conditionals"; domain terms: `{c: ... - else: ...}`, CONST dispatch |
| User/persona with specific characteristics | PASS | Ava — Swift developer; The Intercept's heavy use of both forms cited |
| 3+ domain examples with real data | PASS | `score = 11` if/else; `outcome = 2` switch; `outcome = 99` else fallthrough |
| UAT in Given/When/Then (3–7 scenarios) | PASS | 5 scenarios |
| AC derived from UAT | PASS | 5 AC lines |
| Right-sized (1–3 days, 3–7 scenarios) | PASS | ~4 hours; 5 scenarios |
| Technical notes: constraints/dependencies | PASS | Conditional divert / branch-jump note; dependency on C1 stated |
| Dependencies resolved or tracked | PASS | C1 must ship first; tracked in story-map.md |
| Outcome KPIs defined | PASS | KPI 2 in outcome-kpis.md |

### DoR Status: PASSED

---

## Story C3 — Ink Functions

| DoR Item | Status | Evidence |
|---|---|---|
| Problem statement clear, domain language | PASS | "Engine does not support function call frames"; `f()` divert, `~ret`, `"void"` node named |
| User/persona with specific characteristics | PASS | Ava — The Intercept uses 2 functions; context is explicit |
| 3+ domain examples with real data | PASS | `greet("Cass")` → `"Hello, Cass."`; temp variable assignment; save/restore across call site |
| UAT in Given/When/Then (3–7 scenarios) | PASS | 5 scenarios |
| AC derived from UAT | PASS | 6 AC lines including `returnStack` balance and void-suppression |
| Right-sized (1–3 days, 3–7 scenarios) | PASS | ~6 hours; 5 scenarios |
| Technical notes: constraints/dependencies | PASS | `f()` JSON encoding, `~ret`, `"void"` node documented; dependency on none (independent) |
| Dependencies resolved or tracked | PASS | T3 (ref params) depends on C3; tracked in story-map.md |
| Outcome KPIs defined | PASS | KPI 3 in outcome-kpis.md |

### DoR Status: PASSED

---

## Story T1 — Single-Level Tunnel

| DoR Item | Status | Evidence |
|---|---|---|
| Problem statement clear, domain language | PASS | "Story stalls at `->->`"; `->t->`, `returnStack`, `->->` named |
| User/persona with specific characteristics | PASS | Ava — story with 8+ tunnels matching The Intercept |
| 3+ domain examples with real data | PASS | Caller/sub_room/post-tunnel text sequence; multiple callers; save/restore at tunnel boundary |
| UAT in Given/When/Then (3–7 scenarios) | PASS | 5 scenarios |
| AC derived from UAT | PASS | 6 AC lines including `returnStack` balance and `canContinue` |
| Right-sized (1–3 days, 3–7 scenarios) | PASS | ~6 hours; 5 scenarios |
| Technical notes: constraints/dependencies | PASS | `->t->` JSON encoding, ADR-004 `returnStack` re-use, inklecate encoding verification step |
| Dependencies resolved or tracked | PASS | T2 depends on T1; T1 and C3 independent; tracked in story-map.md |
| Outcome KPIs defined | PASS | KPI 4 in outcome-kpis.md |

### DoR Status: PASSED

---

## Story T2 — Nested Tunnels

| DoR Item | Status | Evidence |
|---|---|---|
| Problem statement clear, domain language | PASS | "Outer return address lost during inner tunnel"; `returnStack`, LIFO, nesting depth named |
| User/persona with specific characteristics | PASS | Ava — story with at least one two-level tunnel nesting (The Intercept) |
| 3+ domain examples with real data | PASS | Caller→A→B→A-post→caller-post sequence; `returnStack.count` = 2 at peak; save/restore at peak depth |
| UAT in Given/When/Then (3–7 scenarios) | PASS | 4 scenarios |
| AC derived from UAT | PASS | 6 AC lines including `returnStack.count` assertions |
| Right-sized (1–3 days, 3–7 scenarios) | PASS | ~4 hours; 4 scenarios |
| Technical notes: constraints/dependencies | PASS | No new components; ADR-004 validation; `@testable import` for stack inspection; dependency on T1 |
| Dependencies resolved or tracked | PASS | T1 must ship first; tracked in story-map.md |
| Outcome KPIs defined | PASS | Embedded in KPI 4 (tunnel continuation) |

### DoR Status: PASSED

---

## Story T3 — Reference Parameters

| DoR Item | Status | Evidence |
|---|---|---|
| Problem statement clear, domain language | PASS | "Caller variable not updated"; `{"^var": "name", "ci": N}`, context index, callstack frame named |
| User/persona with specific characteristics | PASS | Ava — The Intercept uses 2 functions with ref params; cited explicitly |
| 3+ domain examples with real data | PASS | `add(ref score, 10)` → `"10"`; three sequential calls → `"15"`; save/restore |
| UAT in Given/When/Then (3–7 scenarios) | PASS | 4 scenarios |
| AC derived from UAT | PASS | 5 AC lines |
| Right-sized (1–3 days, 3–7 scenarios) | PASS | ~4 hours; 4 scenarios |
| Technical notes: constraints/dependencies | PASS | Variable pointer JSON, `ci` context index, spike findings reference; dependency on C3 stated |
| Dependencies resolved or tracked | PASS | C3 must ship first; tracked in story-map.md |
| Outcome KPIs defined | PASS | KPI 5 in outcome-kpis.md |

### DoR Status: PASSED

---

## Overall DoR Summary

| Story | DoR Status |
|---|---|
| C1 — Inline Conditional Text | PASSED |
| C2 — Block and Switch Conditionals | PASSED |
| C3 — Ink Functions | PASSED |
| T1 — Single-Level Tunnel | PASSED |
| T2 — Nested Tunnels | PASSED |
| T3 — Reference Parameters | PASSED |

**All 6 stories pass DoR. Feature is ready for DESIGN wave handoff.**

---

## Peer Review: Confirmation Bias and Completeness Check

### Dimension 0 — Elevator Pitch Test

All 6 stories have `### Elevator Pitch` with Before/After/Decision enabled lines.

- Before lines reference a concrete observable failure (wrong text, stall, void literal, unchanged variable).
- After lines reference `story.continue()` / `story.currentText` / `story.currentChoices` — all are user-invocable API entry points, not internal functions. PASS.
- Concrete output specified (text content, void absence, continuation behaviour). PASS.
- Decision enabled lines name a real developer decision (shipping without host-app workarounds). PASS.

### Dimension 1 — Confirmation Bias

**Happy path bias check**: All 6 stories include at least one save/restore scenario (boundary/error path). C1 and C2 include false-branch scenarios. C3 includes void-return suppression. T1 and T2 include premature-ending prevention scenarios. T3 includes sequential mutation accumulation. No happy-path-only stories. PASS.

**Technology bias**: No stories prescribe `evalStack` implementation details as requirements. Technical notes sections are advisory, not prescriptive. PASS.

### Dimension 2 — Completeness

**Error scenarios present**: E1–E5 in journey-developer-visual.md; each story has at least one failure scenario (false branch, void output, premature end, unchanged variable). PASS.

**NFRs**: Save/restore invariant is a system constraint applied to every story. Zero regression is a guardrail KPI. No performance NFRs — this is a library with no latency requirements in scope. PASS.

**Missing scenario check (JTBD job-map gates)**:
- Define: "inklecate compiles cleanly before engine work starts" — covered in journey Step 1 failure modes.
- Confirm: "false positive from wrong oracle" — addressed by frozen `InkSwift` module constraint and regression KPI.
- Monitor: "misleading green test" — addressed by oracle comparison requirement (test must compare against InkStory, not just assert non-empty).

### Dimension 4 — Testability

All AC items are testable by `XCTAssertEqual` on `story.currentText` or `@testable import` on `returnStack.count`. No vague AC ("it should work correctly") present. PASS.

### Verdict: APPROVED for DESIGN wave handoff
