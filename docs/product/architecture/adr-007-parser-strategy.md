# ADR-007: Parser Strategy — Hand-Rolled Recursive-Descent / Combinator Port

**Status**: Accepted (user-confirmed 2026-06-14)
**Date**: 2026-06-14
**Deciders**: Maarten Engels (project owner), Morgan (nw-solution-architect)
**Feature**: native-ink-compiler

---

## Context

The compiler must parse `.ink` source into an AST. The reference C# compiler (`StringParser.cs`, 685 lines) is a hand-written, single-phase recursive-descent parser operating directly on a `char[]`, with a combinator vocabulary (`OneOf`, `OneOrMore`, `Optional`, `Exclude`, `Interleave`, `Peek`, `ParseUntil`), a rule-state stack for zero-cost backtracking, and per-character line/column tracking that feeds `DebugMetadata` onto every node.

Ink's grammar is **context-sensitive**: choice/gather depth is indentation-counted; list literals are disambiguated from parenthesised expressions by speculative parse-and-backtrack; inline `{...}` logic disambiguates expression vs conditional vs sequence by ordered speculative attempts. The feasibility research (`docs/research/ink-compiler-feasibility.md`, Findings 1-3) evaluated three Swift options and **recommends a hand-rolled parser for Phase 0** to stay close to the C# mental model, with swift-parsing as a possible later refactor.

The architecture brief carries a hard guardrail: **no new runtime dependencies** introduced by the new module (Technology Stack section; guardrail metric in the DISCUSS KPIs).

**Quality attributes for this decision**: Correctness (semantic fidelity to inklecate), No new runtime dependencies (hard guardrail), Maintainability, Testability, and low risk of semantic mismatch during the port.

---

## Decision

Adopt a **hand-rolled recursive-descent / combinator parser**, ported directly from the C# `StringParser` design, living in `Compiler/Parser/`.

- A small Swift combinator core (~300 lines per research) carrying a `Substring`/`String.Index` cursor plus a rule-state stack and line/column tracking.
- The C# `customFlags` mutable-context approach is replaced by an **explicit parser-context value/parameter** in Swift (per research guidance) rather than shared mutable reference flags.
- Position tracking (line/column) is captured on the cursor and attached to AST nodes, feeding the located-error model (ADR-009).
- A Pratt (operator-precedence) sub-parser handles the expression grammar (14 binary operators / 8 precedence levels), copied directly from the C# precedence table.

---

## Alternatives Considered

### Option B — swift-parsing (Point-Free)

A maintained OSS combinator library (v0.14.x, MIT, result-builder syntax, zero-copy on `Substring.UTF8View`).

**Evaluation**:
- Mature, well-maintained OSS; combinator vocabulary (`OneOf`, `Many`, `Optionally`, `Skip`, `Prefix`) maps closely to `StringParser`.
- **Introduces a new runtime/build dependency** into `SwiftInkRuntime` — directly contrary to the brief's hard "no new runtime dependencies" guardrail (architecture brief, Technology Stack section: "No new runtime dependencies are introduced by `SwiftInkRuntime`"; DISCUSS guardrail metric: "no new runtime dependencies introduced"). This guardrail reflects the project's Portability goal (Linux/WASM future, brief Quality Attribute Strategies). The feasibility research (Finding 2) independently recommends hand-rolling for semantic-fidelity reasons. The compiler lives inside `SwiftInkRuntime` (ADR-006 Option A), so a swift-parsing dependency would attach to the runtime module that the project deliberately kept dependency-free (only Foundation).
- swift-parsing is value-semantics-first; the C# parser threads mutable context. Translating context handling is tractable but adds an impedance-mismatch layer on top of the dependency cost.
- No independent benchmark vs hand-rolled for Ink-complexity grammars (research Gap 2); performance is irrelevant for a document compiler, so this is not a deciding factor either way.

**Rejection rationale**: Violates the no-new-dependency guardrail for the runtime module. The ergonomic benefit does not outweigh attaching a dependency to a module whose dependency-freedom is an established quality attribute (Portability — Linux/WASM future, brief Quality Attribute Strategies).

### Option C — ANTLR4 (Swift target)

Generate a parser from a declarative ANTLR grammar.

**Evaluation**:
- Mature tool (v4.13.2), Swift target available.
- Ink's context-sensitivity (indent-counting, list-vs-paren disambiguation) is hard to express in ANTLR's LL(*) form without semantic predicates; the C# parser is explicitly procedural to handle exactly these ambiguities. Research Finding 3 recommends against ANTLR4 for this project.
- Adds a code-generation build step and an ANTLR runtime dependency — again contrary to the guardrail.

**Rejection rationale**: Grammar mismatch with Ink's context-sensitivity plus a build-tool/runtime dependency. Explicitly not recommended by the feasibility research.

---

## Consequences

**Positive**:
- Zero new dependencies — the guardrail holds; `SwiftInkRuntime` stays Foundation-only.
- Closest possible mapping to the authoritative C# reference, minimising semantic-mismatch risk (the dominant correctness risk per research).
- Full control over speculative parsing / backtracking, which Ink's disambiguation rules require (Risks 2 and 3 in the research).
- Line/column tracking is first-class, directly serving ADR-009's located errors.

**Negative**:
- More hand-written code than adopting a library (~300-line combinator core plus per-construct rules). Mitigated: this is the same code shape the C# reference already proves, and the bounded scope (rows 1-35 only) removes the most expensive parser rules (lists, sequences, threads) from the *supported* path — they become reject-detections, not full parse rules.
- The team owns the combinator engine's maintenance. Acceptable for a single-developer project that already owns a hand-written tree-walker runtime.

**Revisit trigger**: If, after the supported set is complete, parser ergonomics become a maintenance burden, a refactor to swift-parsing may be reconsidered — but only if the no-dependency guardrail is explicitly relaxed by the project owner. The combinator boundary is internal to `Compiler/Parser/`, so such a swap would not affect the codegen or output contract.
