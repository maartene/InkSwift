# ADR-009: Error Model — Single-Error-Then-Stop, Located, with Construct-Named Rejections

**Status**: Accepted (user-confirmed 2026-06-14)
**Date**: 2026-06-14
**Deciders**: Maarten Engels (project owner), Morgan (nw-solution-architect)
**Feature**: native-ink-compiler

---

## Context

DISCUSS decision **D2** requires that unsupported constructs (matrix rows 25-28, 36-39) be **rejected with a clear, located error, never compiled silently** (US-06). The user's hardest constraint is "never fail silently." DISCUSS explicitly scopes the error model to **single-error-then-stop**; multi-diagnostic recovery is recorded as out of scope (a future enhancement). US-07 publishes a supported/unsupported reference the error should point to.

The parser (ADR-007) tracks line/column on its cursor, so located errors are available from position data already captured. The C# `StringParser.Expect()` supports an optional `recoveryRule` for multi-diagnostic continuation — a capability the bounded scope deliberately does NOT adopt.

**Quality attributes for this decision**: Reliability (no silent wrong output — the feature's central guardrail), Usability (the author can act on the error immediately), Correctness (rejection set == the inverse of the runtime-supported set), and Testability (corpus-level "no construct compiles silently" guarantee).

---

## Decision

Adopt a **single-error-then-stop, located error model** with construct-named rejection diagnostics.

- The compile entry point yields **either** a runnable story **or** a single structured `CompileError` (Swift `throws`). It never yields a partial/silently-degraded story.
- **`CompileError` format** (signature shape, not implementation): `CompileError(kind: CompileErrorKind, message: String, line: Int, column: Int?)`, conforming to `Error` (and `Equatable` for test assertions). `message` MUST name the construct (e.g., "LIST declaration", "variable-text sequence", "external function", "thread") and its reason (e.g., "runtime has no list support"). For unsupported constructs, `message` MUST also point at the US-07 reference (e.g., "… — see the supported-feature reference"). `column` is optional because not every detection site has column-level position.
- `CompileError` carries: a **kind** (e.g., `unsupportedConstruct`, `syntaxError`, `unresolvedReference`), a **human-readable message naming the construct** (e.g., "variable-text sequence", "LIST declaration", "external function", "thread"), and a **source location** (line, and column where available) derived from the parser's position tracking.
- For unsupported constructs (rows 25-28, 36-39), the message names the construct and points the author to the US-07 feature reference ("see the supported-feature reference").
- **Reject-list**: each unsupported construct is detected during compilation by a dedicated detection rule. Detection is independent of the supported-feature codegen slices and is recommended to land alongside S1 (per the slice map / S6 priority) so unsupported input cannot slip through silently while S1-S5 are being built.
- A corpus-level guarantee (US-06 AC): a corpus of `.ink` sources, one unsupported construct each, must each stop with a named, located error and produce no story.
- The bounded supported set is the inverse of the reject set: the compiler's accepted set == the runtime's playable set (D1). Accepting more than the runtime plays is silent breakage and is forbidden.

---

## Alternatives Considered

### Option B — Multi-diagnostic recovery (report many errors per compile)

Port the C# `recoveryRule` mechanism so one compile reports every error it can find.

**Evaluation**:
- Better authoring ergonomics for large files (see all problems at once).
- **Explicitly out of DISCUSS scope** (recorded as a future enhancement). Recovery rules add substantial parser complexity (state rollback, error-node synthesis, continued-parse correctness) for a capability the bounded MVP does not need.
- Single-error-then-stop fully satisfies the user's actual constraint ("never fail silently; name the construct and where it is").

**Rejection rationale**: Out of scope per DISCUSS; complexity unjustified for the bounded feature. Re-openable later without redesign — the `CompileError` type can grow to a `[CompileError]` return without changing the located/named-construct contract.

### Option C — Boolean/optional failure (compile returns nil or false on any problem, no structured error)

The entry point returns an optional story; `nil` means "did not compile."

**Evaluation**:
- Simplest possible signature.
- **Directly violates D2/US-06**: a bare `nil` names no construct and reports no location — it is the "unclear failure" the feature exists to eliminate. It also cannot distinguish "unsupported construct" from "syntax error," which the AC requires.

**Rejection rationale**: Fails the feature's defining requirement (clear, located, construct-named errors). Non-starter.

---

## Consequences

**Positive**:
- The feature's central guardrail (zero silent wrong output) is structurally enforced: the only outcomes are "runnable story" or "named, located error."
- Located, construct-named errors are directly testable by the unsupported-construct corpus (one construct per fixture), giving the US-06 corpus-level guarantee a concrete test shape.
- Pointing the error at the US-07 reference closes the loop between the error model and the published feature reference (doc-vs-compiler consistency, US-07 AC).
- Detection landing alongside S1 means every later slice is built against a compiler that refuses what it cannot (or will never) handle.

**Negative**:
- Authors with multiple unsupported constructs in one file fix them one compile at a time. Accepted per scope; re-openable as Option B later with no contract change.
- Each unsupported construct needs its own detection rule and a matching corpus fixture — a finite, enumerable surface (rows 25-28, 36-39 = 9 constructs grouped as: variable-text sequences/cycles/once/shuffle, threads, LIST, RANDOM/SEED_RANDOM, externals).

**Enforcement / test obligation**: the doc-vs-compiler consistency check (US-07) asserts that every construct's documented status (supported/rejected) matches actual compiler behaviour, closing the gap between the reference document and the reject-list.
