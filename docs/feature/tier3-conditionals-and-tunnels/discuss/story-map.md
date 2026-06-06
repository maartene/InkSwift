# Story Map — tier3-conditionals-and-tunnels

## User: Ava (Swift game developer integrating SwiftInkRuntime)
## Goal: Run a story that uses conditional text, functions, and tunnels and get output matching the JS-bridge oracle

---

## Backbone (User Activities — from the story author's / developer's perspective)

| A1 — Write conditional text | A2 — Write Ink functions | A3 — Write tunnels | A4 — Write reference parameters |
|---|---|---|---|
| Inline `{c: a\|b}` | `=== function f(x) ===` | `-> knot ->` | `=== function f(ref x) ===` |
| Block `{c: ...}` / `{else: ...}` | Inline call `{f(x)}` | Nested tunnels | Caller variable mutated by function |
| Switch `{v: - 1: ... - 2: ...}` | `~ temp = f(x)` assignment | `->->` return | |

---

## Walking Skeleton

Not applicable — brownfield. The engine already boots (Tier 1) and choice mechanics work (Tier 2). The first slice of Tier 3 extends an already-working engine.

---

## Scope Assessment: PASS — 7 stories, 2 bounded contexts (Engine/Decoder), estimated 7 days

The 7 stories span two bounded contexts (the eval stack / tree-walker for conditionals and functions; the call-return stack for tunnels). Each story is 1–3 days. The dependency graph is linear within each sub-feature. No need to split further.

---

## Slices (each ≤1 day, ordered by dependency and outcome impact)

### Sub-feature A: Conditional Text and Functions (independent of tunnels)

#### Slice C1 — Inline Conditional Text (A1 row 1)
**Brief coverage**: Row 22 `{c: a|b}` — UNKNOWN, no test
**Goal**: `{condition: true-text|false-text}` inline alternation produces correct output based on the condition value.
**IN scope**: Inline binary conditional `{c: a|b}`; both branches; condition derived from variable or literal.
**OUT scope**: Block conditionals, switch conditionals, functions, tunnels.
**Learning hypothesis**: `{metCass: You know her.|She's a stranger.}` outputs `"You know her."` when `metCass` is true. If wrong branch appears, the inline conditional evaluator is not dispatching correctly.
**Effort**: ~4 hours

#### Slice C2 — Block Conditionals (A1 rows 2–3)
**Brief coverage**: Row 23 (if/else if) and Row 24 (switch-style) — UNKNOWN, no test
**Goal**: `{c: ... - else: ...}` block form and `{v: - 1: ... - 2: ...}` switch dispatch produce correct output.
**IN scope**: if/else block; switch-style (value matching); fallthrough to else branch.
**OUT scope**: Functions, tunnels.
**Learning hypothesis**: `{ score > 10:\n    You passed.\n- else:\n    You failed. }` outputs the correct branch. If both branches appear or neither appears, the block evaluator is mishandling the conditional jump.
**Effort**: ~4 hours

#### Slice C3 — Ink Functions (A2)
**Brief coverage**: Rows 29–30 (`=== function f(params) ===`, `{f()}` calls) — UNKNOWN, no test
**Goal**: An Ink function called inline produces its return value in the output stream. A function called with `~ temp = f(x)` assigns the return value to the temp variable.
**IN scope**: Function definition and call; single parameter; return value; `"void"` suppressed from output; function callstack survives save/restore.
**OUT scope**: Reference parameters (Slice C4), tunnels.
**Learning hypothesis**: `{greet("Cass")}` in story output produces `"Hello, Cass."`. If `"void"` appears or the text is empty, the `~ret` / `f()` call frame is not being cleaned up correctly.
**Effort**: ~6 hours

---

### Sub-feature B: Tunnels and Reference Parameters (depend on call-return stack from ADR-004)

#### Slice T1 — Single-Level Tunnel (A3)
**Brief coverage**: Row 34 — MISSING, ADR-004 deferred; `->->` is the return command
**Goal**: `-> sub_knot ->` executes the sub-knot and then continues the calling knot after the `->` site.
**IN scope**: Single tunnel entry and return (`->t->` push + `->->` pop from `returnStack`); post-tunnel text is correct; tunnel body text is correct; tunnel survives save/restore.
**OUT scope**: Nested tunnels (Slice T2), reference parameters (Slice T3).
**Learning hypothesis**: `-> the_interview ->` executes `the_interview`, then the story continues with the text after the tunnel call. If the story stalls or ends prematurely, the `returnStack` push/pop is not wired.
**Effort**: ~6 hours

#### Slice T2 — Nested Tunnels (A3 deep)
**Brief coverage**: Row 34 — ADR-004 explicitly notes tunnels can be nested (`A -> B -> C -> B -> A`)
**Goal**: A tunnel inside a tunnel executes correctly; return addresses stack correctly and unwind in LIFO order.
**IN scope**: Two-level tunnel nesting; correct unwinding; state survives save/restore.
**OUT scope**: Reference parameters.
**Learning hypothesis**: `-> A ->` where `A` calls `-> B ->` exits B correctly into A, then exits A into the caller. If A's continuation is skipped or B's continuation is used for A's return, the stack is not being pushed/popped with correct depth.
**Effort**: ~4 hours

#### Slice T3 — Reference Parameters (A4)
**Brief coverage**: Row 35 — MISSING; `{"^var": "name", "ci": N}` variable pointer
**Goal**: `=== function add(ref total, n) ===` mutates the caller's variable when the function executes.
**IN scope**: Single `ref` parameter; caller variable updated after function returns; save/restore preserves updated variable.
**OUT scope**: None — this is the last Tier 3 slice.
**Learning hypothesis**: After calling `add(ref score, 10)`, `{score}` in output shows the incremented value. If unchanged, variable pointer resolution is not looking up the correct callstack frame.
**Effort**: ~4 hours

---

## Priority Rationale

| Priority | Slice | Value | Urgency | Effort | Score | Rationale |
|---|---|---|---|---|---|---|
| 1 | C1 — Inline conditionals | 5 | 5 | 2 | 12.5 | Most common Ink idiom (95+ uses in The Intercept); blocks all realistic story testing |
| 2 | C2 — Block/switch conditionals | 5 | 5 | 2 | 12.5 | Required by The Intercept's CONST dispatch; completes the conditional family |
| 3 | C3 — Functions | 4 | 4 | 3 | 5.3 | The Intercept uses 2 functions; needed for ceiling proof but less frequent |
| 4 | T1 — Single-level tunnels | 5 | 4 | 3 | 6.7 | The Intercept uses 8 tunnels; single-level is the prerequisite for all tunnel work |
| 5 | T2 — Nested tunnels | 3 | 3 | 2 | 4.5 | The Intercept may use one nesting level; validates ADR-004 call-return model fully |
| 6 | T3 — Reference parameters | 2 | 2 | 2 | 2.0 | Required by The Intercept's 2 functions with ref params; can defer if time constrained |

**Dependency order overrides priority where required:**
- C2 depends on C1 (block conditionals need the inline evaluator foundation)
- T2 depends on T1 (nested tunnels need single-level wired first)
- T3 depends on C3 (ref params need function callstack frames)

**Tie-breaking applied**: Riskiest assumption → C1 (if the inline conditional evaluator is wrong, C2 and C3 tests will all be meaningless). After C1, priority follows Value × Urgency / Effort.
