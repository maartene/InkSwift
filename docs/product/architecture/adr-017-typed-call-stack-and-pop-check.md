# ADR-017: Typed Call-Stack Elements and Type-Checked Tunnel/Function Pops

**Status**: Accepted (maintainer confirmed Option A, empty-stack refusal included, 2026-11-17)
**Date**: 2026-11-17
**Deciders**: Maarten Engels (project owner), Morgan (solution architect)
**Feature**: typed-runtime-paths (issue #25)
**Refines**: ADR-004 (return address stack in `StoryState`)

---

## Context

ADR-004 introduced `StoryState.returnStack: [String]`. It now holds two string grammars on
one stack: tunnel returns `"path.N"` (`buildTunnelReturnAddress`) and function returns
`"fnret:path|N"` (`buildFunctionReturnAddress`). (`.pushDivertTarget` no longer uses it — it
pushes onto `evalStack` — so the ADR-004 text is stale on that point.) Kind is told apart
only by `hasPrefix("fnret:")`:

- `->->` pops whatever is on top and hands it to `applyDivert`. With a function return on
  top, `"fnret:…"` fails to resolve → **silent no-op**, execution walks on.
- `~ret` with a tunnel return on top does nothing and walks on.
- `->->` or `~ret` on an empty stack does nothing and walks on.

Reference: `CallStack.Element` carries `PushPopType` (`Tunnel`, `Function`,
`FunctionEvaluationFromGame`); `CanPop(type)` / `Pop(type)` check it (`CallStack.cs:326-345`).
On `->->`/`~ return` mismatch `Story.cs:1275-1288` calls
`Error("Found {tunnel onwards statement (->->) | function return statement (~ return)}, when expected {…| end of flow (-> END or choice)}")`;
`Error` throws a `StoryException` that `Continue` catches into `AddError`, which calls
`state.ForceEnd()` (`Story.cs:2838-2857`). With no `onError` handler, `Continue` then throws.

InkSwift's runtime has no error model: `Story.continue()` is non-throwing and
`currentErrors` returns `[]` (`InkEngine.swift:137`). ADR-009 governs *compile* errors only.
The conformance harness already reads `story.currentErrors` (`hadError`).

## Upstream check (CLAUDE.md "before matching a reference bug")

The refusal is a **deliberate, named error in the reference, not a defect**. `Story.cs`
PopFunction/PopTunnel handling (~lines 1255-1297): when
`state.callStack.currentElement.type != popType || !state.callStack.canPop` it calls
`Error(string.Format("Found {0}, when expected {1}", …))` with the names
`function return statement (~ return)` / `tunnel onwards statement (->->)`, and
`end of flow (-> END or choice)` when the stack cannot pop. Searches of inkle/ink issues
(`gh api search/issues`; terms "Found tunnel onwards statement", "Found function return
statement", "when expected", "tunnel return function error", "callstack pop tunnel") found no
report calling the check a defect. The only hit for the message, inkle/ink#466 (closed 2018),
is a user correctly hitting it on a documentation example. So matching the reference here is
copying a design decision, not a bug.

## Decision

Option A, with the empty-stack case included:

1. **Element type** (`Engine/CallStack.swift`):
   `CallStackElement { kind: CallKind; returnPath: ContainerPath; returnIndex: Int }`,
   `CallKind` = `tunnel` | `function`. `FunctionEvaluationFromGame` is omitted (no
   `EvaluateFunction` API exists); add it with that feature. `returnStack` becomes
   `[CallStackElement]`, persisted per ADR-018.
2. **Type-checked pops**: `->->` pops only a `tunnel` element; `~ret` and implicit
   function-body exhaustion pop only a `function` element.
3. **On mismatch or empty stack**: refuse the pop, append a runtime error to the engine's
   error list surfaced by `currentErrors`, and end the flow (`isEnded = true`, so
   `canContinue == false`). Public API unchanged. The message is the **exact C# text**,
   `Found {popped}, when expected {expected}`, where *popped* / *expected* are
   `tunnel onwards statement (->->)` or `function return statement (~ return)`, and
   *expected* is `end of flow (-> END or choice)` when the stack is empty. For example:
   `Found tunnel onwards statement (->->), when expected function return statement (~ return)`.
4. **Delivery**: the type change (behaviour-preserving, mismatch still a no-op) and the
   refusal ship as separate slices; the refusal slice carries ATs for `->->` over a function
   frame, `~ret` over a tunnel frame and the empty stack, each with content after the
   construct (CLAUDE.md "a fixture must continue past the construct").

## Alternatives Considered

### Option B — refuse and throw a new `StoryError` from `continue()`
Matches C#'s no-handler path. **Rejected**: `continue()` is non-throwing and
`@discardableResult`; making it `throws` breaks every consumer call site for an error only
malformed stories trigger.

### Option C — refuse silently (type-check, keep walking)
No observable change beyond not corrupting the stack. **Rejected**: keeps the
silent failure the issue reports; contradicts the project's "never fail silently" stance
(ADR-009 spirit) and leaves `currentErrors` a permanent stub.

### Option D — `preconditionFailure`
Fail-fast in debug. **Rejected**: a malformed story would crash the host app in release.

### Scope variant — refuse only kind mismatches, keep the empty-stack no-op
Smaller behaviour change. **Rejected** (D2-scope = yes): the reference errors on the empty
stack too (`end of flow (-> END or choice)`), and the empty case is the same silent failure.

## Consequences

**Positive**: the bug class "tunnel return consumes a function frame" becomes a checked
refusal; `currentErrors` gets its first producer, reusing the reference message text, and is
immediately visible to the conformance harness; no public API change.

**Negative**: stories that today "work by accident" past a mismatched or empty pop now stop
with an error. Mitigation: full oracle + conformance suite per slice; any fixture that trips
it is investigated before deciding to keep it.

**Error lifetime** (decided 2026-11-17, maintainer): runtime errors live in memory only,
outside `StoryState`, and are never saved. A story has no way to recover from a runtime
error, so saving one would only persist an unrecoverable state, and errors are not meant
as a diagnostics record. `restoreState` and `moveToKnot` clear them, since both start from
a different position.

Per-call temp scopes (`callFrameVariables`) and
`functionRootDepths` parallel C# `Element.temporaryVariables`; folding them into
`CallStackElement` is a possible follow-up, not part of this decision.
