# DISTILL Upstream Issues — tier3-conditionals-and-tunnels

**Wave**: DISTILL  
**Date**: 2026-06-05  
**Source**: inklecate fixture inspection during scenario writing

These issues were discovered by compiling real Ink source fixtures with inklecate and
inspecting the resulting JSON. They represent gaps between the DESIGN wave documents and
actual inklecate output. The crafter MUST consult this file before implementing each slice.

---

## Issue 1 — `"out"` control command is absent from DESIGN documents

**Severity**: HIGH — blocks C3 (functions) implementation  
**Source file**: `docs/feature/tier3-conditionals-and-tunnels/design/wave-decisions.md`  
**Discovered in**: `slice-c3-functions.ink.json`

**Finding**: Every function call site in inklecate-compiled JSON contains an `"out"` control
command immediately after the `{"f()": path}` divert node, inside the enclosing `ev`/`/ev`
block. The `"out"` command pops the top value from `evalStack` and outputs it to the text
stream. For void-returning functions, the popped value is a `"void"` literal which must be
suppressed (not emitted as text).

**Evidence**:
```json
"c-0": [
    "^The result is ",
    "ev",
    5,
    {"f()": "double"},
    "out",           ← not mentioned in DESIGN
    "/ev",
    "^.",
    ...
]
```

**Implication for crafter**:
1. `TreeWalker.handleControlCommand` must add a `case "out":` handler
2. The handler pops the top of `evalStack`
3. If the value is `.voidValue` (or `InkValue.void`): no output (suppress)
4. If the value is any other `InkValue`: convert to string and push to `outputStream`

The `"out"` command is distinct from the `"ev"` eval context end `/ev` — the `ev`/`/ev`
block merely marks the eval region; `"out"` explicitly transfers the top value to output.

---

## Issue 2 — `"pop"` control command is absent from DESIGN documents

**Severity**: MEDIUM — blocks T3 (reference parameters) implementation  
**Source file**: `docs/feature/tier3-conditionals-and-tunnels/design/wave-decisions.md`  
**Discovered in**: `slice-t3-ref-params.ink.json`

**Finding**: The T3 ref-params call site uses `"pop"` (not `"out"`) after the `{"f()": "add"}`
call. This is used when the function's return value is not needed (the side-effect of mutating
the ref param is the goal).

**Evidence**:
```json
"start": [
    "ev",
    {"^var": "score", "ci": -1},
    10,
    {"f()": "add"},
    "pop",           ← not mentioned in DESIGN
    "/ev",
    ...
]
```

**Implication for crafter**: `TreeWalker.handleControlCommand` must add a `case "pop":` handler
that pops and discards the top of `evalStack` without outputting.

---

## Issue 3 — Variable pointer `ci` field uses `-1` for globals, not `0`

**Severity**: HIGH — DESIGN assumed `ci == 0` for globals; inklecate uses `ci == -1`  
**Source file**: `docs/feature/tier3-conditionals-and-tunnels/design/wave-decisions.md` D5  
**Discovered in**: `slice-t3-ref-params.ink.json`

**Finding**: The DESIGN document states "ci is the callstack context index: 0 = globals scope,
1 = outermost active call frame". Inklecate actually compiles `add(ref score, 10)` with
`{"^var": "score", "ci": -1}`. The `ci == -1` value is used for global scope.

**Evidence**:
```json
{"^var": "score", "ci": -1}
```

**Implication for crafter**: The `.variablePointer` NodeKind case and InkEngine handler must
treat `ci == -1` as "global scope" (look up in `state.variablesState`), not `ci == 0`.
The DESIGN document's `ci == 0` assumption is incorrect.

**T3 deferral gate update**: Since the actual `ci` for global variables in The Intercept is
`-1` (not 0), the deferral condition described in design/wave-decisions.md still holds —
if `ci == -1` everywhere in The Intercept's ref-param functions, the simple global-scope
lookup is sufficient (no `callFrameVariables` stack needed).

---

## Issue 4 — Void functions end at `null` without explicit `"~ret"`

**Severity**: MEDIUM — function call-return mechanism must handle implicit void return  
**Source file**: `docs/feature/tier3-conditionals-and-tunnels/design/wave-decisions.md` D3  
**Discovered in**: `slice-c3-functions.ink.json`

**Finding**: The `setSideEffect` function (void — no explicit `~ return` in Ink source)
ends with `null` in the JSON. There is no `"~ret"` node. The function must return control
to the caller when it reaches the end of its container (`null`).

**Evidence**:
```json
"setSideEffect": [
    "ev",
    true,
    "/ev",
    {"VAR=": "sideEffect", "re": true},
    null          ← no "~ret" — engine must detect end-of-function-container
]
```

**Implication for crafter**: The InkEngine step loop must detect when execution reaches the
`null` end-of-container node for a function call frame (i.e., when `returnStack` is non-empty
after the function was entered via `{"f()": path}`). At that point:
1. Push a void value to `evalStack` (so the call site `"out"` command has something to suppress)
2. Pop `returnStack` and `applyDivert` to the return address

Alternatively: the `"~ret"` handler is the only return mechanism, and void functions need
inklecate to insert an implicit `"~ret"` — but this is NOT what the fixture shows. The
engine must handle the `null`-end implicit return.

**Design amendment needed**: D3 in `design/wave-decisions.md` states "The `~ret` control
command pops `returnStack` and diverts to the return address." This is still correct for
functions with explicit `~ return`. But it must be supplemented with the implicit-return
behaviour for void functions.

---

## Issue 5 — Engine diverges from oracle starting at line 11 on non-trivial Intercept path (DISTILL addendum 2026-06-06)

**Severity**: MEDIUM-HIGH — blocks the new DWD-07 non-trivial playthrough acceptance test
**Source file**: engine output divergence between native `Story` and `InkSwift.InkStory`
**Discovered in**: `TheInterceptNonTrivialPlaythroughTests` (Milestone5b)

**Initial summary (incorrect)**: an earlier version of this entry said the
divergence was a single extra line at index 67. That was a misreading of
the failure log — Swift Testing's `for i in 0..<prefix` loop reports each
mismatched index, and the LAST few visible in the trail are 67-79 because
the test loop continues past the first failure.

**Corrected finding**: driving the engine through the committed non-trivial
choice script produces **69 line mismatches**, the FIRST at index 11. Lines
0-10 match the JS-bridge oracle exactly. The divergence onset is the line
emitted immediately after picking choice 3 — `* {tellme} [Deny] "I'm not
pretending anything." ... Harris looks disapproving. -> pushes_cup` in the
`waited` knot of The Intercept (source line 119).

**Observed divergence at the onset**:
```
N011 = "Harris looks disapproving. He pushes one mug halfway towards me:"
O011 = "Harris looks disapproving. He pushes one mug halfway towards me: a small gesture of friendship."
N012 = "I take a mug and warm my hands. It's a small gesture of friendship."
O012 = "Enough to give me hope?"
```

Then native's choice trace shows it re-enters the OUTER cluster with
`count=2, options=["Take one", "Wait"]` after the `Deny` body completes,
whereas the oracle has correctly advanced past the cluster to the next
choice cluster `count=2, options=["Take it", "Don't take it"]`. The
remaining 67 mismatches downstream are knock-on effects of being in a
different scene with different `teacup`/`forceful` state.

**Hypothesised mechanism**: after picking a bracketed once-only `*` choice
whose body ends with `-> labeled_gather` (where `labeled_gather` is a
depth-2 gather inside the same choice cluster), the native engine emits the
labeled-gather content correctly, but then re-enters the choice cluster
loop instead of advancing to the depth-1 parent gather. The mismatch is
NOT a glue / text-flush bug — it's a flow control bug around how the
container stack collapses after diverting to an intra-cluster label.

**Reproducer attempts (all of which FAILED to reproduce in isolation)**:
1. `slice-bug-glue-after-choice.ink` — minimal 2-choice cluster with `<>`
   glue after a no-bracket choice → passes.
2. Same fixture extended to nested choice clusters (outer bracketed +
   inner) with glue-tail gather → passes.
3. Same again with explicit `-> labeled_gather` divert inside the cluster
   → passes.
4. Faithful copy of the Intercept's `waited` knot structure (4 choices, two
   with `-> pushes_cup`, one with content + glue, one bare; same
   conditional gating on `tellme` / `cooperate`; same depth-2 labeled
   gather plus depth-1 parent gather) → still passes.

The slice fixture
`Tests/SwiftInkRuntimeTests/slice-bug-glue-after-choice.ink.json` plus
`Bug_GlueAfterChoiceTests` is kept as a regression guard for the patterns
that DO work. It does NOT reproduce the Intercept divergence.

**Implication for next DELIVER feature**: open a focused bugfix feature.
Investigation will need engine-level instrumentation: trace native vs.
oracle through the same script with `containerStack`, `returnStack`,
`evalStack`, `chosenChoiceTargets`, `currentChoices`, and `pointer.path`
at every step around the Deny-cluster exit. The combination of accumulated
state from earlier choices (Wait → "Tell me what..." → Deny) is required
to trigger the bug — narrowing it without that state has so far failed.

**Update 2026-06-06 — Partial fix landed**: a lockstep engine-state trace
revealed the root cause: `InkEngine.parseRelativePath` was counting carets
as **execution-stack frames** (`containerStack.count - caretCount`), but
the canonical C# runtime counts carets as **compiled path-component depth**
(verified against `ink-engine-runtime/Path.cs:220-223` and `Object.cs:106-123`,
where each caret returns `Container.parent` — the static tree parent set
at JSON-load time). When `applyDivert` resolved a relative path with
multi-component descent (e.g. `.^.^.c-6.3.pushes_cup`), it pushed ONE frame
for the destination with a `pathFromRoot` of 3 extra components but only
1 extra frame on the stack. Subsequent relative diverts from that
destination (like the 5-caret `.^.^.^.^.^.g-2` exiting `pushes_cup`)
overshot their intended anchor by N components.

The fix changes `parseRelativePath` to compute the anchor from the top
frame's `pathFromRoot.dropLast(caretCount - 1)`, and introduces a
`installDestinationFrame` helper that replaces the stack with the
destination frame plus preserved strict-prefix ancestors (propagating
`isChoiceContinuationRoot` from discarded frames). The four callers
(`applyDivert`, `applyConditionalBranch`, `buildContinuationFrames`,
`resolveRelativePath`) plus `resolveReadCountKey` and
`resolveToAbsoluteComponents` are updated to use the new API. See the
commit titled `fix(engine): caret math counts path-component depth, not stack-frame depth`.

**Result**: the original line-11 divergence is **resolved**. The
non-trivial Intercept playthrough test now matches the oracle line-for-line
through index 15. The full pre-existing suite (148 tests) stays green —
zero regressions.

**Remaining gaps (deferred to a follow-on bugfix feature)**:

1. ~~Line 16 — glue not preserved across function-call diverts~~. **FIXED 2026-06-06.**
   The `stepToNextLine` loop was flushing pending lines at the start of
   `ev`/`/ev` eval blocks, before the function-call divert + destination
   glue could remove the trailing `\n`. The fix adds an `evalBlockDepth`
   counter that defers flushes while inside an `ev`/`/ev` block; also
   makes `flushRemainingOutput` line-aware (drains one complete line at
   a time via `consumeNextLine` instead of merging the whole buffer);
   and allows `canContinue` to return true while complete lines remain
   in the output buffer (so trailing buffered lines drain across
   subsequent `continue()` calls even after the story has ended). Lines
   0-20 of the non-trivial playthrough now match the oracle (was 0-10
   before the eval-block fix). See the commit
   `fix(engine): defer line flush inside ev/.../ev eval blocks`.
2. ~~Char ~1318 — real content divergence at the Panic/Calculate/Deny
   cluster due to function-local `temp= x` leakage~~. **FIXED 2026-06-06.**
   `TreeWalker.handleVariableAssignment` and `handleVariableReference`
   were writing/reading BOTH `VAR=` (global) and `temp=` (function-local)
   into the single `state.variablesState` dict, so the first
   `~ raise(forceful)` call's leftover `x` pointer corrupted the second
   `~ raise(evasive)` call. The fix implements the deferred T3 DESIGN
   D5 Option A: a `callFrameVariables: [[String: InkValue]]` per-frame
   scope on `StoryState`, pushed by `applyFunctionCall` and popped by
   `applyFunctionReturn`. `temp=` writes go to the top frame; reads
   check local first then fall back to globals. Result: after
   `~ raise(forceful); ~ raise(evasive)`, `forceful=0` and `evasive=1`
   correctly (was `forceful=float(1.0)`, `evasive=0`). At the
   Panic/Calculate/Deny cluster: all three choices visible (was just
   Calculate/Deny). Lines 0-27 of the non-trivial playthrough now match
   the oracle (was 0-20). See the commit
   `fix(engine): per-frame temp variable scope for function calls`.

3. **Line 28+ — Say-nothing conditional choice filtered (still open)**.
   At the "You want to explain that?" cluster in the `admitted_to_something`
   knot, the native engine shows only `[Explain]` where the oracle shows
   `[Explain, "Say nothing"]`. The `Say nothing` choice is gated by
   `{drugged}`, and `drugged=int(1)` at the relevant moment, no stale
   function-frames on the stack, so the bug looks unrelated to bug 2.
   Slice 02 (conditional choice gating) tests still pass — the basic
   mechanism works for simpler fixtures. The compiled JSON for this
   cluster has a deeply-nested ev/.../ev structure inside an outer
   `{not drugged}` conditional gather body. Possibly an interaction
   between the new `evalBlockDepth` tracking and how nested choice
   conditions get evaluated, or an unrelated quirk in the conditional
   branch handling. Deferred to a separate bugfix feature; diagnosis
   should start by adding evalStack-snapshot instrumentation at
   `collectChoicePoint` and comparing native vs. oracle stack states
   step-by-step through the cluster.

The committed regression test `Bug_GlueAfterChoiceTests` covers the
glue-after-choice patterns that DO work, as a baseline against which any
future fix can be validated without regression.

**Why it was not caught by Tier 3 slice tests OR the always-pick-0
ceiling proof**: slice fixtures isolate single mechanisms; always-pick-0
on The Intercept loops on "Think" in the opening cluster and never reaches
a choice with `* [Bracketed] -> labeled_gather` structure inside a
depth-2-gated `*` choice cluster. The non-trivial playthrough's varied
choice sequence is the first test in the suite that explores this
combination.

---

## Summary Table

| Issue | Severity | Blocks | DESIGN gap? |
|-------|----------|--------|-------------|
| `"out"` command unhandled | HIGH | C3, T3 | YES — not mentioned |
| `"pop"` command unhandled | MEDIUM | T3 | YES — not mentioned |
| `ci == -1` for globals | HIGH | T3 | YES — assumed `ci == 0` |
| Void function implicit `null` return | MEDIUM | C3 | YES — only `~ret` described |
| Flow control after `* [Bracketed] -> labeled_gather` re-enters cluster | MEDIUM-HIGH | DWD-07 test | engine bug, not design (corrected diagnosis 2026-06-06) |
