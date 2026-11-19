# ADR-025: One Native-Function Catalog Shared by Compiler and Runtime; Compile-Time Call Resolution

**Status**: Accepted (maintainer, 2026-11-19 — option C1(c); POW and string `?`/`!?` implemented now). Revised after design review, 2026-11-19.
**Date**: 2026-11-19
**Deciders**: Maarten Engels (project owner), Morgan (solution architect)
**Feature**: reference-fidelity-backlog (issue #36)
**Amends**: ADR-009 (the reject-list names now come from the catalog and match the runtime's names)

---

## Context

Built-in names are defined in three unrelated places:

- the decoder's sets (`InkDecoder.swift:21-48`);
- `TreeWalker`'s `String` switch with `default: break` (`TreeWalker.swift:321-360`);
- the compiler's `UnsupportedConstructDetector`, which emits `construct` strings that differ
  from the runtime's `UnsupportedFeature` names. The detector names RANDOM `"random"`
  (`:58`) and uses the bare keywords `"list"`, `"thread"`, `"external"` and `"include"`
  (`:44-60`). The runtime uses `"RANDOM()"`, `"LIST"`, `"threads (<-)"` and
  `"EXTERNAL functions"` (`InkDecoder.swift:30-50`, asserted in
  `Engine_UnsupportedFeatureLoadTests.swift:29-33`).

The compiler resolves no call. `ExpressionLowering.lowerFunctionCall` emits
`.functionCall(target: name)` for every call (`:91-107`), and `.unresolvedReference` is never
produced. As a result:

- Undefined or misspelled functions and all built-ins compile silently.
- At runtime the unresolved call leaks a function frame, a temp scope and a body depth, and
  the last argument prints.

SEED_RANDOM is inconsistent between the two paths:

- The runtime deliberately **accepts** `srnd`, because without the RNG tokens a seed has no
  observable effect (`InkDecoder.swift:17-25`).
- The compiler **rejects** `SEED_RANDOM(` through `containsRandomCall`
  (`UnsupportedConstructDetector.swift:72-76`).

**Reference.** `FunctionCall.GenerateIntoContainer` checks, in order:

1. the special built-ins: CHOICE_COUNT, TURNS, TURNS_SINCE, READ_COUNT, RANDOM, SEED_RANDOM,
   LIST_RANGE, LIST_RANDOM;
2. `NativeFunctionCall.CallExistsWithName`, with an arity check;
3. list constructors;
4. a user function, whose unresolved target becomes "not found".

(`FunctionCall.cs:35-229`.) `SeedRandom` pops the seed and pushes `Void`
(`Story.cs:1517-1528`).

## Decision

1. **`Decoder/NativeFunctionCatalog.swift` (new)** is the single table. Each entry has:
   - the author-facing source name;
   - the runtime token;
   - the arity;
   - a status: *supported*, or *unsupported*.

   Unsupported entries carry the author-facing name used in errors. Supported entries form an
   internal enum. Unsupported **statement-level constructs** (thread, LIST declaration,
   EXTERNAL, INCLUDE, shuffle) are listed in the same file under the same names, so the
   compiler and the decoder share one vocabulary. INCLUDE has no runtime counterpart; its name
   becomes `"INCLUDE"`.
2. **Runtime.**
   - `InkDecoder`'s sets derive from the catalog.
   - `NodeKind.nativeFunction` carries the enum.
   - `TreeWalker` switches **exhaustively** over it, with no `default:`.
3. **`NodeKind.nativeFunction` migration — every construction site**:
   - `ExpressionLowering.swift:64`: binary operators.
   - `ExpressionLowering.swift:66`: unary operators.
   - `VariableTextEmitter.swift:120-137`: `MIN`, `%`, `==` for sequence dispatch.
   - `ConditionalEmitter.swift:413`: the literal `.nativeFunction("==")`.
   - `InkDecoder.classifyString` (`:255`).

   Each site maps to the enum. The SwiftLint ban on `.nativeFunction("` string construction
   then holds everywhere.
4. **Compiler call resolution** in `ExpressionLowering`, in the reference's order:
   1. An unsupported special built-in → a located `.unsupportedConstruct`, with the catalog
      name as `construct`.
   2. A supported native → an arity check (a mismatch is a located `.syntaxError`: "X should
      take N parameter(s)"), then the argument nodes and `.nativeFunction`.
   3. A user function in `LoweringContext.functions` → `.functionCall`.
   4. Anything else → a located `.unresolvedReference` ("Function call target not found: X").

   **Throws ripple**: `lowerExpression` (`ExpressionLowering.swift:46-49`) and
   `lowerFunctionCall` (`:91-95`) are non-throwing today and become `throws`. Their callers
   must propagate:
   - the statement lowerers in `RuntimeObjectEmitter`;
   - `lowerInlineExpression`;
   - the guard and subject closures handed to `ConditionalEmitter` and `WeaveEmitter`, and
     those emitters' closure parameter types.

   Errors are located through `CompileError.locating` at the statement sites, which hold the
   positions.
5. **Built-in support after this ADR:**
   - **Newly supported**: `POW` (int and int give a float, as C# `(float)Math.Pow`), and
     string `?` and `!?`. The expression tokenizer learns both operators. Their behaviour for
     non-string, non-list operands is a DELIVER probe.
   - **SEED_RANDOM is accepted on both paths.** The compiler compiles it to `srnd`, and the
     runtime's `srnd` pushes a void value after popping the seed, as C# does, so the `pop`
     emitted for a discarded call stays balanced. This is the default the maintainer may
     override. Without RANDOM a seed changes nothing observable, so accepting it plays
     exactly as the reference does.
   - **Still rejected, located, under the runtime's names** on both paths: `RANDOM()`,
     `TURNS()`, `TURNS_SINCE()`, `CHOICE_COUNT()`, `READ_COUNT() of a divert-target variable`,
     `shuffle {~a|b}`, `LIST`.
6. **Consistency test.** For every unsupported catalog entry, the compiler's `construct`
   equals the runtime's `UnsupportedFeature.name`.

## Alternatives Considered

- **A second hard-coded list in the compiler.** **Rejected**: a fourth copy of the names is
  the cause of #36.
- **Resolve calls in a separate post-parse validation pass.** **Rejected for now**:
  `ExpressionLowering` already has the function table, and a second walk duplicates it.
  Revisit if the warning channel (#38) arrives.
- **Keep the old `construct` strings** to avoid a user-visible change. **Rejected**: it keeps
  two vocabularies, which is the defect this ADR removes.
- **Keep POW and `?`/`!?` refused.** **Rejected** by the maintainer.
- **Keep SEED_RANDOM rejected in the compiler.** **Rejected by default**: it leaves the two
  paths inconsistent with no observable benefit.

## Consequences

**Positive**
- Nothing compiles silently.
- Built-ins play correctly when compiled natively.
- One vocabulary for unsupported features across compiler and runtime.

**User-visible changes (release-note callouts)**
- **Undefined function calls no longer compile**, as in inklecate.
- **`CompileError.construct` strings change** to the runtime's names. For example, `"random"`
  becomes `"RANDOM()"`, `"list"` becomes `"LIST"`, `"thread"` becomes `"threads (<-)"`,
  `"external"` becomes `"EXTERNAL functions"`, and `"include"` becomes `"INCLUDE"`. The type
  and its fields are unchanged, so this is not API-breaking, but hosts that match on these
  strings must update. `Compiler_S6_UnsupportedRejectionTests.swift:24-29` is updated in the
  same step.
- **SEED_RANDOM now compiles natively.**

**Release split**
- Call resolution and the rejections fix #36: **patch**.
- POW and `?`/`!?`: **minor**.
- Update the differences doc (footnote ², "At a glance") and the feature reference.
