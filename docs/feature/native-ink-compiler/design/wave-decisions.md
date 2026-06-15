# DESIGN Wave Decisions — native-ink-compiler

**Feature**: native-ink-compiler | **Wave**: DESIGN | **Architect**: Morgan (nw-solution-architect)
**Date**: 2026-06-14 | **Mode**: PROPOSE | **Density**: lean
**Status**: ADRs 006-009 PROPOSED pending project-owner confirmation of four forks.

---

## Decision Proposal — Four Decisive Forks (relay to user)

### Fork 1 — Output contract / module placement (DISCUSS OQ#3, the central fork)

| Option | One-line trade-off |
|---|---|
| **A — Co-locate `Compiler/` inside SwiftInkRuntime; internal `StoryBlueprint(root:)`** | True no-JSON D3, R2 preserved (NodeKind stays internal), needs new rule R5; module grows. |
| B — Separate compiler module reaching node types via `@_spi`/`package` | Parallel modules, but pierces R2's encapsulation and relies on an underscored Swift feature. |
| C — Compiler emits JSON; story built via `StoryBlueprint(json:)` | Simplest, preserves all boundaries, max reuse — but a real JSON round-trip; relegates D3 to "logically in-process" and inverts D3/D4. |

**Recommendation: A** — it is the only option that honors D3 literally ("no JSON
round-trip") while preserving R2; the runtime's `InkDecoder` already proves the
node tree is the natural shared seam. C is the clean fallback if the owner values
boundary minimalism + JSON-as-oracle over a strict no-round-trip path.

### Fork 2 — Parser strategy (DISCUSS OQ#1)

| Option | One-line trade-off |
|---|---|
| **A — Hand-rolled recursive-descent/combinator port of C# StringParser** | No new dependency (honors guardrail), closest C# mapping, more hand-written code. |
| B — swift-parsing (Point-Free) | Mature OSS combinators, but a NEW dependency on a deliberately dependency-free runtime module. |
| C — ANTLR4 | Declarative grammar, but mismatched to Ink's context-sensitivity + a build-tool dependency. |

**Recommendation: A** — the "no new runtime dependencies" guardrail is decisive
(the compiler lives inside the Foundation-only runtime module per Fork 1A); also
the research-recommended choice and lowest semantic-mismatch risk.

### Fork 3 — Weave-resolution spike (DISCUSS OQ#2, highest research risk)

| Option | One-line trade-off |
|---|---|
| **A — Spike-gate the S3 slice plan** | De-risks the single highest-risk algorithm before committing slice sizing/codegen structure; adds a discrete spike step. |
| B — Design-through (specify, implement in S3) | Faster to "start S3", but concentrates the top risk inside a committed slice with no checkpoint. |
| C — Full upfront `Weave.cs` port in DESIGN | Maximally de-risks, but over-builds and inverts walking-skeleton-first ordering. |

**Recommendation: A** — both the research and DISCUSS risk register call for it;
the gate is objective (oracle line/choice identity) and its container-construction
pattern becomes the codegen template, reducing rework. Gate: PASS on flat + nested
+ labeled-gather + sealed-weave corpus → commit S3; FAIL in time box → re-scope
S3 open-weave-first.

### Fork 4 — Error model (DISCUSS OQ#5)

| Option | One-line trade-off |
|---|---|
| **A — Single-error-then-stop, located, construct-named** | Matches DISCUSS scope + the "never fail silently" constraint exactly; one fix per compile. |
| B — Multi-diagnostic recovery | Better ergonomics, but explicitly out of DISCUSS scope; substantial parser complexity. |
| C — Boolean/optional failure | Simplest signature, but violates D2/US-06 (names no construct, reports no location). |

**Recommendation: A** — fully satisfies the user's defining requirement; re-openable
to B later with no contract change (the `CompileError` type can grow to a list).

---

## Architecture Summary

- **Pattern**: ports-and-adapters within a modular package. Compiler = a new
  bounded responsibility (`Compiler/` layer) with one driving port (compile entry)
  and driven adapters (source/INCLUDE filesystem read; test-only oracle).
- **Paradigm**: Object-Oriented with value-type state (project-established). The
  parsed AST and `ContainerNode` output are value types; the pipeline stages are
  composable.
- **Pipeline / components**: CommentEliminator → StringParser/combinators →
  InkParser (statement rules + Pratt expressions) → typed parsed AST →
  WeaveResolver (spike-gated) → RuntimeObjectEmitter (AST → `ContainerNode`/
  `NodeKind`; D6 obligations) → `StoryBlueprint(root:)` → `Story`. Optional
  JSONEmitter sink (D4). CompileError reporter on parse/codegen failure.
- **Integration**: codegen reuses the runtime's internal `ContainerNode`/`NodeKind`
  as its output, converging with `InkDecoder` on one consumer contract. New
  internal `StoryBlueprint(root:)` is the no-JSON D3 seam.

## Reuse Analysis (outcome)

REUSE/EXTEND for every runtime integration point: `ContainerNode`, `NodeKind`,
`ChoiceFlags`, `StoryBlueprint` (+internal init), `Story` (+compile entry),
`InkDecoder` (+probe pattern), the oracle test harness, and existing fixtures
(incl. `TheIntercept.ink` as the comprehensive end-to-end oracle). CREATE NEW is
confined to the genuinely-new compiler pipeline (lexer, parser, AST, weave
resolver, codegen emitter, error reporter, JSON emitter, source IO adapter,
compiler entry) — no compilation stage exists today, so extending is impossible.
**Zero unjustified CREATE NEW.**

## Technology Stack

Swift tools 5.8+ (raise from 5.6); Foundation only (no `JSONSerialization` in
`Compiler/` — R5); hand-rolled parser (no new dependency); `JSONEncoder`/string
for secondary JSON; Swift Testing/XCTest reusing the existing oracle harness;
inklecate as test-only oracle; SwiftLint enforcing R1/R3 + new R5.

## Constraints Established

- **R5** (Compiler-layer isolation) added; R1/R2/R3/R4 unchanged.
- Frozen `InkSwift` module untouched (D8).
- Compiler accepted set == runtime supported set (D1); over-acceptance = silent
  breakage, forbidden.
- No new runtime dependency (guardrail holds).
- D3 (no JSON round-trip) honored literally by Fork 1A.

## Upstream Changes

**None.** No DISCUSS locked decision (D1-D8) is reversed; all DISCUSS Open
Questions #1-#7 are resolved without contradiction. The recommended Fork 1A
preserves D3 verbatim, so no `## Changed Assumptions` block and no
`design/upstream-changes.md` are required. (If the owner overrides Fork 1 to
Option C, a Changed Assumptions entry re-characterising D3 as "logically
in-process" would be added at that time.)

## ADRs

- ADR-006 — Compiler Output Contract and Module Placement (Fork 1) — PROPOSED
- ADR-007 — Parser Strategy (Fork 2) — PROPOSED
- ADR-008 — Weave-Resolution Spike Gate (Fork 3) — PROPOSED
- ADR-009 — Error Model (Fork 4) — PROPOSED

## Open Questions Deferred to DISTILL/DELIVER

1. Container-naming normalisation for Level-2 structural JSON comparison.
2. S3 a/b/c split sizing (post weave-spike).
3. S2 a/b split sizing.
4. Public compile-entry surface shape (`InkCompiler.compile` vs `Story.init(inkSource:)`).
5. Exact `CompileError` case enumeration (discovered during DELIVER RED).

---

# DESIGN Wave Decisions — weave-label read-count addressing slice

**Feature**: native-ink-compiler | **Wave**: DESIGN | **Architect**: Morgan (nw-solution-architect)
**Date**: 2026-06-15 | **Mode**: PROPOSE | **Scope**: application/component | **Density**: lean
**ADR**: ADR-011 (Weave-Label Read-Count Addressing) — Accepted, **Option B CHOSEN**.
**Slice**: dotted read-count references to named weave labels (`{knot.label: text}` → `.readCount(path)`), descoped from `compiler-variable-text` slice-04 (user-approved 2026-06-15).

## Chosen Approach & Provenance (locked 2026-06-15)

**Option B CHOSEN** — incremental label→path table via an extended `LoweringContext` + a discovery pre-pass — explicitly grounded in the original inkle/ink C# compiler. Governing heuristic: *when in doubt, follow the original.* Option B maps one-to-one onto inklecate's **three-phase** weave-naming algorithm:

1. **Discovery pre-pass** = `Weave.ResolveWeavePointNaming()` (`Weave.cs:81-100`) — registers **only labelled** weave points (unlabelled `g-N`/`c-N` are not name-addressable) and collects the read-count-referenced label SET.
2. **Resolver's cached absolute path** = `GenerateRuntimeObject` (labelled containers also named by their label, `Gather.cs:21-24`).
3. **`lowerExpression` → `.readCount(path)`** = `VariableReference.ResolveReferences()` (`VariableReference.cs:87-142`), which **reads the cached `runtimePath` and never re-derives** (`:111`) and flags `0x1` CountVisits only on the resolved target (`:101`).

Option A (re-walk + re-derive paths) is rejected because re-deriving paths is precisely what the original avoids; Option C (standalone resolver) is rejected because the original fuses naming/path/keying into `Weave`/`Gather`, so a separate component would duplicate or couple tightly to that work.

## Key Decisions

- **[WL-D1] Minimal EXTEND of the existing emitter pipeline; no new component.** The "deferred WeaveResolver" already shipped as `WeaveEmitter` (DELIVER S3) and already owns weave structure, the `c-N`/`g-N` namespace, gather-`(label)` keying, and absolute-path construction. (ADR-011)
- **[WL-D2] Parse choice `(label)` + `{condition}` guard; add `weaveLabel`/`condition` to the AST `choice` case.** Reuses the generic `splitBracketedLabel`. (CompilerAST.swift / InkParser.swift)
- **[WL-D3] Label-keyed choice containers** (`label ?? "c-N"`, mirroring `gatherKey`). (WeaveEmitter.swift)
- **[WL-D4] Set `flags = 0x1` (CountVisits) on read-count-referenced labelled containers ONLY** (the discovery-pre-pass SET), not eagerly on every labelled container — matching the original (`VariableReference.cs:101`; `countAllVisits` OFF for normal compiles). The runtime tracks only flagged containers' visits (incl. choice bodies). (WeaveEmitter.swift; runtime `InkEngine.swift:1043`)
- **[WL-D5] `weaveLabelPaths` (labelled-only) table on `LoweringContext`, populated incrementally during resolution + a discovery pre-pass** (Option B — CHOSEN over post-pass / new component; matches inklecate three-phase). (RuntimeObjectEmitter.swift)
- **[WL-D6] `lowerExpression` emits `.readCount(resolvedAbsolutePath)` on a label-resolved dotted reference**, else falls through to `.variableReference` — exactly as the original treats a non-resolving single-component name as a variable read (`VariableReference.cs:129-141`). (RuntimeObjectEmitter.swift)
- **[WL-D7] No runtime/Engine/Decoder change; Level-1 execution-equivalence; compiler emits its OWN resolved path.** (ADR-011 / D5)

## Architecture Summary

- **Pattern**: unchanged — ports-and-adapters within the modular `Compiler/` layer; one driving port (`InkCompiler.compile`), no new driven port.
- **Paradigm**: object-oriented/imperative (CLAUDE.md) — value-type `enum`/`struct` emitters, matching `WeaveEmitter`/`ConditionalEmitter`.
- **Flow change**: `InkParser` (choice `(label)`/`{condition}`) → `CompilerAST` (extended `choice`) → `WeaveEmitter` (label-keyed + `0x1`-flagged containers, registers label→path into `LoweringContext`) → `RuntimeObjectEmitter.lowerExpression` (`.readCount(path)`). Runtime consumes unchanged.

## Reuse Analysis

| Existing Component | File | Overlap | Decision | Justification |
|---|---|---|---|---|
| `WeaveEmitter` (shipped "WeaveResolver") | `Compiler/Codegen/WeaveEmitter.swift` | weave structure, namespace, gather-label keying, absolute paths | **EXTEND** | Already does gather label-keying + path building; add choice keying + `0x1` flag + table write at the existing site. New component would duplicate the traversal. |
| `RuntimeObjectEmitter` / `LoweringContext` | `Compiler/Codegen/RuntimeObjectEmitter.swift` | `.variableReference` lowering; table threading | **EXTEND** | The wrong emission is one branch; `LoweringContext` already threads CONST + function tables. |
| `InkParser` / `splitBracketedLabel` | `Compiler/Parser/InkParser.swift` | choice/gather + bracketed-label parsing | **EXTEND** | Helper is already delimiter-generic; reuse with `(`/`)` for choices. |
| `CompilerAST` `choice` | `Compiler/AST/CompilerAST.swift` | choice AST shape | **EXTEND** | Two additive fields; `gather` already carries `label`. |
| `.readCount` + CNT?/CountVisits | `Decoder/`, `Engine/` | read-count resolution + visit tracking | **REUSE AS-IS** | Fully implemented runtime-side; forbidden to change (R1/R3/R5). |
| `ChoiceFlags`, divert path resolution | `Engine/`, `WeaveEmitter` | flag bitfield; absolute path arithmetic | **REUSE AS-IS** | Single source of path truth shared with divert targets. |

**Zero CREATE NEW.**

## Technology Stack

Swift (existing); Foundation only; no new dependency; no `Package.swift` change; no new `NodeKind` case (reuses `.readCount`). Object-oriented value-type emitters.

## Constraints Established

- R1/R3/R5 SwiftLint boundary unchanged and binding: `Compiler/` imports no `Engine/`, no `JSONSerialization`.
- No runtime/Engine/Decoder change (the read-count machinery is complete).
- Correctness gate: Level-1 execution-equivalence — the two re-enabled ATs + a focused weave-label read-count fixture. Mutation testing disabled (CLAUDE.md).
- `0x1` CountVisits flag set on labelled containers ONLY (avoid altering unrelated read-count semantics).

## Upstream Changes

**None.** No DISCUSS/prior-DESIGN decision is reversed. This slice realises the descoped follow-up recorded in `docs/evolution/2026-06-15-compiler-variable-text.md`. The two `.disabled` ATs (TheIntercept e2e + dotted read-count RED pin) re-enable on green, discharging the consciously-waived "zero `.disabled` at finalize" exception.

## Open Questions Deferred to DISTILL/DELIVER

1. **WL-OQ1** — Confirm the `TheIntercept` dotted reference targets a choice-body label vs a gather (oracle path `…0.g-1.c-14`). WL-D3/D4 handle both uniformly.
2. **WL-OQ2** — `{condition}`-guarded choice combining a guard with a dotted read-count (`{a.b > 1}`) — composes via `lowerExpression`; verify with a fixture.
3. ~~**WL-OQ3** — Label-vs-qualified-variable disambiguation~~ — **ANSWERED by the original**: a table miss falls through to `.variableReference`, matching inklecate's treatment of a non-resolving single-component name as a variable read (`VariableReference.cs:129-141`). No design question remains.
4. **WL-OQ4** — Choice `(label)` vs sibling stitch/gather name collision in `namedContent`; assert no silent overwrite (located error if it occurs).
