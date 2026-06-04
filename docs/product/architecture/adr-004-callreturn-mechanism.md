# ADR-004: Call/Return Mechanism — Return Address Stack in StoryState

**Status**: Accepted
**Date**: 2026-06-04
**Deciders**: Maarten Engels (project owner), Morgan (nw-solution-architect)
**Feature**: native-runtime (ink-callreturn-mechanism)

---

## Context

The Ink compiler emits a call/return pattern for every choice. The pattern uses three interrelated mechanisms:

1. `{"^->":"path"}` — push a path string onto a stack as a "return address" (divert-target value)
2. `{"->":"$varName","var":true}` — variable divert: pop the return address and navigate to it
3. Anchor resolution — when a path ends in a `$`-prefixed component (e.g., `"0.c-0.$r2"`), the destination is the position *after* that named anchor in its parent container, not the anchor itself

This pattern is structurally a single-level call frame: push the return address before entering a sub-sequence, execute the sub-sequence, then jump to the return address. Future Ink features — tunnels (`-> knot ->`) and functions — use the same mechanism with nesting.

Three options were evaluated for where to carry the return address during execution.

---

## Decision

Add `var returnStack: [String]` to `StoryState`.

- `{"^->":"path"}` (decoded as `.pushDivertTarget(path)`) appends `path` to `returnStack`.
- `{"->":"$r","var":true}` (decoded as `.divert(target: "$r", isConditional: false, isVariable: true)`) causes InkEngine to pop from `returnStack` and use the result as the divert target.
- `returnStack` is part of `StoryState: Codable`. It defaults to `[]` at `init()`. The `Codable` implementation uses `decodeIfPresent` with a `[]` fallback so existing save files are not invalidated.

---

## Alternatives Considered

### Alternative A: `.divertTarget(String)` case added to `InkValue`, carried on `evalStack`

Reuse the existing `evalStack: [InkValue]` by adding a `.divertTarget(String)` case to `InkValue`.

**Evaluation**:
- Zero new fields in `StoryState` — simplest upfront change.
- `InkValue` is used for arithmetic operands. A `.divertTarget` case is semantically orthogonal to `int`, `float`, `string`, `bool`. Any native-function handler that pops from `evalStack` without checking the type would silently consume a return address. This failure mode is invisible at compile time.
- When tunnels or functions are implemented, `evalStack` is the wrong home for call frames. The C# ink runtime uses a dedicated call stack (`callStack`) separate from the evaluation stack. Using `evalStack` now creates a forced migration later.
- Debuggability impact: when inspecting `evalStack` during a test failure, a `.divertTarget` mixed with numeric values is confusing.

**Rejection rationale**: Semantic conflation of execution control with data evaluation. Silent failure mode for native-function handlers. Incompatible with the architecture of tunnels/functions.

### Alternative C: `var pendingReturnTarget: String?` — a single nullable field

A nullable single-value field self-documents the current single-level constraint.

**Evaluation**:
- Semantically accurate for the current feature scope.
- Does not extend to nested returns. Ink tunnels can be nested — `A -> B -> C -> B -> A`. If tunnels are implemented, `pendingReturnTarget` must be replaced with an array, which is a breaking change to the save/restore format (new field name + type).
- The `optional` type communicates "at most one" as a hard constraint, not a current simplification. Future implementors reading the code may not realise it is a simplification rather than a spec constraint.

**Rejection rationale**: Dead-end for tunnels. The migration to an array breaks save/restore format compatibility in a way that `returnStack` (already an array) does not.

---

## Consequences

**Positive**:
- `returnStack` correctly models the Ink call/return mechanism at the type level — it is a stack of addresses, not a value operand.
- Future tunnel support appends return addresses to the same stack. No field replacement, no save/restore format break.
- `StoryState` remains fully `Codable`. The `returnStack` field is included in save/restore automatically. Existing save files decode correctly (field absent → `[]` via `decodeIfPresent`).
- `evalStack` remains clean — only arithmetic/logic operands. No silent cross-contamination.
- `InkValue` is not extended. The enum exhaustiveness constraint (NodeKindTests pattern) does not apply to `InkValue`, but keeping `InkValue` focused reduces cognitive load.

**Negative**:
- `StoryState.init()` and the `Codable` implementation must be updated. This is a mechanical change — one new field, one `decodeIfPresent` line.
- `returnStack` is a stack but Swift has no `Stack` type — it is implemented as `[String]` with `append`/`removeLast`. The stack contract is implicit in how callers use it, not enforced by the type system. A code comment in `StoryState` documents this intent.

---

## Component Impact

| Component | Change | Scope |
|---|---|---|
| `StoryState` | Add `var returnStack: [String]` | Engine layer — additive |
| `NodeKind` | Add `.pushDivertTarget(String)`; extend `.divert` with `isVariable: Bool` | Decoder layer — additive + parameter extension |
| `InkDecoder.classifyDict` | Detect `^->` → `.pushDivertTarget`; detect `var:true` on `->` → `.divert(..., isVariable: true)` | Decoder layer — additive |
| `TreeWalker.dispatch` | Handle `.pushDivertTarget` (append to `returnStack`); handle `isVariable` flag on `.divert` | Engine layer — additive |
| `InkEngine` | Add `resolveAnchor(inPath:)` method; extend `applyDivert` to use it for `$`-prefixed path tails | Engine layer — additive |
| `NodeKindTests` | Add `.pushDivertTarget` to exhaustive array; update `.divert` arm arity | Test layer — compiler-enforced |

No new components. No new files. No changes outside `Decoder/` and `Engine/`.
