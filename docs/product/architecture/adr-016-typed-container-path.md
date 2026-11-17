# ADR-016: Typed Container Paths and Function-Call Diverts

**Status**: Accepted (maintainer confirmed Option A + function-call case + `DivertTarget`, 2026-11-17)
**Date**: 2026-11-17
**Deciders**: Maarten Engels (project owner), Morgan (solution architect)
**Feature**: typed-runtime-paths (issue #25)

---

## Context

`SwiftInkRuntime` carries container paths as strings with encoded meaning: dotted
`"start.waited.0.g-2"` or `[String]` whose numeric entries are child indices
(`ContainerFrame.pathFromRoot`, `StoryPointer.containerPath`, `visitCounts` keys,
`chosenChoiceTargets`, `.readCount` keys); relative paths `".^.^.name"` whose carets
`InkEngine.parseRelativePath` counts; and function-call diverts tagged `"f():"`, spelled
independently in `InkDecoder.swift:170`, `ExpressionLowering.functionCallTargetPrefix`,
`InkEngine.followDivert` and `RuntimePathReconciler.isReconcilableDivertTarget`. Paths are
re-split, `Int(component)`-tested and re-joined on every step. This is the Primitive
Obsession CodeScene reports in `InkEngine.swift`.

The C# reference types all of it: `Path.cs` (list of `Component`, each index or name, `^`
as parent, `isRelative`), `Divert.cs` (`pushesToStack` + `stackPushType`, not a prefix).

Constraints: the `.ink.json` boundary stays string-based (paths parsed once, in
`InkDecoder`); R1/R3/R5 hold; the native compiler builds `NodeKind` directly (ADR-006
Option A) and its secondary `JSONEmitter` does not serialise diverts — so `f():` belongs to
no output contract.

Quality attributes: correctness (behaviour-preserving), maintainability, enforceability.

## Decision

Option A (two path types), the distinct `.functionCall` case, and `DivertTarget`:

1. **Two path types plus a component** in `Decoder/ContainerPath.swift`:
   - `PathComponent` = `index(Int)` | `name(String)`.
   - `ContainerPath` — absolute, `[PathComponent]`; the only type accepted for state keys
     (visit counts, frames, chosen targets, pointers).
   - `PathReference` = `absolute(ContainerPath)` | `relative(parentSteps: Int, tail: [PathComponent])`
     — the payload of nodes that may be relative.
   - Parse is **total**, with C# `Path.componentsString` semantics: leading `.` = relative,
     leading `^` components counted, int-first component typing, `""` = root. `description`
     reproduces the legacy dotted string; `parse(description) == self` is an invariant.
   - Synthesised `Hashable`; equality is structural, not container identity (index-reached
     and name-reached paths to one container remain distinct keys, as today).
   - The caret *rule* (first caret = object → container) lives in the resolver; the type
     stores the raw count.
2. **`NodeKind` payloads typed**: `readCount(PathReference)` (keys may be relative),
   `choicePoint(target: PathReference, …)`, `tunnelDivert(target: PathReference)`,
   `pushDivertTarget(PathReference)`, and `divert(target: DivertTarget, isConditional:)`
   with `DivertTarget` = `path(PathReference)` | `variable(name: String)` replacing the
   `isVariable` Bool.
3. **Function-call divert = new case `NodeKind.functionCall(target: PathReference)`**,
   parallel to `.tunnelDivert`. `InkDecoder` maps `{"f()": path}` to it; `ExpressionLowering`
   emits it; every `"f():"` literal and `functionCallTargetPrefix` are deleted.
4. **Placement in `Decoder/`**, the lowest layer, so Decoder, Compiler and Engine may all
   depend on it (R1, R5). A symbol-level SwiftLint rule is a recorded follow-up (see
   Enforcement).

## Alternatives Considered

### Option B — one C#-mirror type `InkPath { components incl. .parent, isRelative }`
1:1 with `Path.cs`; the `TestPaths` conformance test ports verbatim. **Rejected**:
relative paths become usable as state keys, and `^` mid-path is representable though
inklecate never emits it. Option A makes both non-representable.

### Option C — `typealias ContainerPath = [PathComponent]`; relative paths and `f():` stay strings
Lowest churn. **Rejected**: leaves the relative-path parsing, the string `NodeKind`
payloads and the triple `f():` spelling — the issue's core findings.

### Function call as a flag — `.divert(…, pushes: CallKind?)` (mirrors `Divert.pushesToStack`)
Most reference-faithful and could absorb `.tunnelDivert`. **Rejected**: every `.divert`
match grows a third field; the reconciler and engine must filter by flag; diverges from the
existing distinct-case style (`.tunnelDivert`).

### Placement in a new `Core/` folder, or in `Engine/`
`Core/` needs a new rule and layout change for one file. `Engine/` would make Decoder and
Compiler depend on Engine — the existing `ChoiceFlags` smell (`Decoder/NodeKind` references a
type in `Engine/StoryState.swift`) should not be repeated.

## Consequences

**Positive**: one parse per path, at the JSON boundary; one concept per type; exhaustive
`switch` on `.functionCall`; `InkEngine` sheds string surgery; the upstream `TestPaths`
conformance test becomes portable (hand port in `scripts/conformance/overrides/`).

**Negative**: ~31 test sites construct `NodeKind` with string payloads and need typed values
(a test-target-only `ExpressibleByStringLiteral` conformance can keep them terse without
letting production code pass raw strings). `PathReference` is a modelling departure from
C#'s single `Path` — documented here.

**Neutral**: the variable-divert site remains the one runtime path parse, because
divert-target *values* are `InkValue.string` (wire format of `variablesState`; out of scope).

## Enforcement

In scope for #25: R2 (`NodeKind` internal) is unchanged; the Swift compiler's
exhaustiveness check enforces `.functionCall` / `DivertTarget` handling; the `parse(description) == self`
round-trip test guards the legacy string form.

Follow-up, **out of scope for #25**: the R1/R5 regexes match only `import Engine` lines,
which never occur inside one module, so symbol-level coupling is unenforced. A
`.swiftlint.yml` rule `r1_r5_no_engine_symbols` over `Decoder/` + `Compiler/` matching
Engine-only type names (`InkEngine`, `StoryState`, `TreeWalker`, `ContainerPathResolver`,
`CallStackElement`) would close it; it cannot cover `ChoiceFlags` until that type moves to
`Decoder/`.
