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

## Summary Table

| Issue | Severity | Blocks | DESIGN gap? |
|-------|----------|--------|-------------|
| `"out"` command unhandled | HIGH | C3, T3 | YES — not mentioned |
| `"pop"` command unhandled | MEDIUM | T3 | YES — not mentioned |
| `ci == -1` for globals | HIGH | T3 | YES — assumed `ci == 0` |
| Void function implicit `null` return | MEDIUM | C3 | YES — only `~ret` described |
