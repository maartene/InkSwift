<!-- markdownlint-disable MD024 -->
# Feature Delta — typed-runtime-paths (DESIGN)

> Tier-1 [REF] sections only (lean). Source: GitHub issue #25. No DISCUSS wave — the
> issue is an internal refactor with one explicit behaviour decision. Architecture SSOT:
> `docs/product/architecture/brief.md` → `### typed-runtime-paths (Feature Addition)`;
> ADR-016, ADR-017, ADR-018. **All decisions accepted by the maintainer, 2026-11-17.**

**One-liner**: Replace the string-encoded container paths, relative paths, return
addresses and `f():` function-call diverts in `SwiftInkRuntime` with value types
mirroring the C# reference (`Path`, `Pointer`, `CallStack.Element`/`PushPopType`,
`Divert.pushesToStack`) — parsed once at the JSON boundary, emitted typed by the native
compiler, persisted in the *existing* save format. Behaviour-preserving except one slice:
type-checked tunnel/function pops.

---

## Wave: DESIGN / [REF] Design Decisions (DDD)

Application scope. Quality attributes (ranked): **Correctness** (behaviour-preserving;
oracle + conformance stay green) > **Reliability** (existing saves restore; a mismatched
pop is no longer silent) > **Maintainability** (Primitive Obsession removed, `InkEngine`
shrinks, one spelling per concept). Paradigm: OOP (CLAUDE.md). Conway: single maintainer —
trivially aligned.

### D1 — Container path type shape and placement — DECIDED: 1A in `Decoder/` (ADR-016)

| Option | Shape | Outcome |
|---|---|---|
| **1A (chosen)** | Two types. `ContainerPath` = absolute, `[PathComponent]`; `PathReference` = `absolute(ContainerPath)` \| `relative(parentSteps: Int, tail: [PathComponent])`; `PathComponent` = `index(Int)` \| `name(String)`. Synthesised `Hashable`. Never-failing parse `init(parsing:)` with C# `Path.componentsString` semantics (int-first; `""` = root; leading `.` = relative; leading `^`s counted). `description` reproduces today's dotted string exactly. | State keys (visit counts, frames, chosen targets) accept only absolute paths — "relative path used as a key" is non-representable. Carets only leading (all inklecate emits). |
| 1B | One C#-mirror type `InkPath { components (incl. `.parent`), isRelative }`. | Rejected: relative paths could reach state keys; `^` mid-path representable. |
| 1C | `typealias ContainerPath = [PathComponent]`; relative paths stay strings. | Rejected: leaves the issue's core findings. |

**Placement**: `Decoder/ContainerPath.swift` — the lowest layer; Decoder, Compiler and
Engine may all depend on it under R1/R5. (`Core/` rejected: new rule + layout change for one
file. `Engine/` rejected: would repeat the `ChoiceFlags` smell.) Caret semantics (first
caret = object→container, no drop) stay in the *resolver*; `parentSteps` stores the raw caret
count. Equality is structural, **not** container identity — the same container reached by
index (`knot.0`) and by name (`knot.c-0`) stays two keys, exactly as today.

### D2 — Call-stack element and mismatched pop — DECIDED: 2A, D2-scope = yes (ADR-017)

Element: `CallStackElement { kind: CallKind (.tunnel | .function), returnPath: ContainerPath, returnIndex: Int }`
on `StoryState.returnStack` (mirrors `CallStack.Element(type, pointer)`).
`FunctionEvaluationFromGame` omitted (no `EvaluateFunction` API). Pops are
`pop(.tunnel)` / `pop(.function)`, mirroring `CallStack.CanPop(type)` / `Pop(type)`.

When the top element has the wrong kind (`->->` over a function frame, `~ret` over a
tunnel frame) **or the stack is empty**: refuse the pop, append the exact C# message to
`currentErrors`, and end the flow (`isEnded = true`). No public API change. Message:
`Found {popped}, when expected {expected}` with `tunnel onwards statement (->->)` /
`function return statement (~ return)`, and `end of flow (-> END or choice)` for an empty
stack.

Rejected: 2B (throw from `continue()` — breaks every caller), 2C (refuse silently — keeps
the silent failure). Upstream check done (CLAUDE.md): the C# refusal is a deliberate named
error (`Story.cs` ~1255-1297); no inkle/ink issue calls it a defect; the only hit,
inkle/ink#466 (closed 2018), is a user correctly hitting it. Recorded in ADR-017.

### D3 — Function-call divert representation — DECIDED: 3A + `DivertTarget` (ADR-016)

The native compiler builds `ContainerNode`/`NodeKind` directly (ADR-006 Option A), and
`JSONEmitter` writes diverts as `"void"`, so **`f():` is in no output contract**. The only
`f()` spelling that survives is the inklecate JSON key `{"f()": path}` in
`InkDecoder.classifyDict`.

- **Chosen**: new case `NodeKind.functionCall(target: PathReference)`, parallel to
  `.tunnelDivert`; `ExpressionLowering.functionCallTargetPrefix`, every `"f():"` literal and
  `RuntimePathReconciler`'s prefix filter are deleted.
- **Chosen (D3-variable)**: `.divert(target: DivertTarget, isConditional: Bool)` with
  `DivertTarget = path(PathReference) | variable(name: String)`, replacing `isVariable`.
- Rejected: 3B (flag on `.divert`, mirrors `Divert.pushesToStack` — every `.divert` match
  grows a field), 3C (centralised prefix — no typing).

### D4 — Save-format compatibility — DECIDED: 4A (ADR-018)

Typed in memory; hand-written `Codable` writes and reads byte-identical legacy strings
(`"fnret:a.b|3"`, `"a.b.4"`, `["a","0"]`, `{"a.b": 1}`); no version field. **Existing saves
must keep restoring**, and new saves restore on the previous build. Path-keyed dictionaries
(`visitCounts`, `chosenChoiceTargets`) map to string keys explicitly in `StoryState`'s
`Codable`, because `CodingKeyRepresentable` dictionary encoding needs macOS 12.3 / iOS 15.4
and the package targets macOS 10.15 / iOS 13. Rejected: 4B (versioned dual reader), 4C
(breaking — contradicts `job-state-durability`).

### D5 — Extraction seam — DECIDED: 5A

`ContainerPathResolver` (`Engine/`): a stateless struct over the immutable `root` —
`node(at:)`, `descend`, relative resolution against a *passed-in* current path (caret rule),
knot-namespace `"0"` flattening (`navigateWithActualPath`), `$`-anchor resolution, and an
ancestor-chain description for stack rebuilding. `InkEngine` keeps all `containerStack`
mutation (`installDestinationFrame`, `applyDivert` family). Rejected for #25: 5B (also
extract a `ContainerStack` type — larger, riskier; possible follow-up), 5C (navigation on
`ContainerNode` in `Decoder/` — splits one concept; possible follow-up).

### D6 — Delivery slicing — DECIDED as below

Trunk-based; every slice commits to `main` with SwiftLint + full `swift test` green.

| Slice | Content | Behaviour |
|---|---|---|
| S0 | Capture **golden legacy saves** from current `main` (mid-tunnel, after a once-only choice, with visit counts, at a choice point) as committed fixtures; restore-and-continue tests. | Test-only — the D4 safety net, captured *before* any type change. |
| S1 | `ContainerPath`/`PathReference`/`PathComponent` in `Decoder/` + unit tests (round-trip `parse(description) == self`, int-first, relative/absolute inequality). Hand-port `TestPaths` (`scripts/conformance/overrides/TestPaths.swift`) and re-enable it. | Additive, no callers. |
| S2 | Extract `ContainerPathResolver` from `InkEngine` (typed API, engine converts at its edges). Check the TreeWalker dead-code candidates (see Follow-ups). | Preserving. |
| S3 | `InkEngine` internals typed: `ContainerFrame.pathFromRoot`, `StoryPointer`, `ContainerStackFrame`, `visitCounts`, `chosenChoiceTargets` → `ContainerPath`, with legacy-string `Codable`. | Preserving; S0 fixtures + round-trip guard the wire. |
| S4 | `NodeKind` payloads typed; decoder parses once; compiler emitters + `RuntimePathReconciler` produce typed values. Delivered as two steps (roadmap 02-03 / 02-04), each changing every construct/match site of its cases in the same commit: **S4a** `readCount`, `choicePoint`, `tunnelDivert`, `pushDivertTarget` → `PathReference`; **S4b** `.divert` `isVariable` → `DivertTarget`. | Preserving. |
| S5 | `NodeKind.functionCall` — decoder `{"f()":…}`, `ExpressionLowering`, engine; delete `functionCallTargetPrefix` and every `"f():"` literal. | Preserving. |
| S6 | `CallStackElement` on `returnStack` with legacy-string `Codable`; `buildTunnelReturnAddress`/`buildFunctionReturnAddress`/`hasPrefix("fnret:")` removed. Mismatched pop still a no-op here. | Preserving. |
| **S7** | **Type-checked pops** per D2 (incl. empty stack): refusal → `currentErrors` (exact C# message) + end. ATs for `->->` over a function frame, `~ret` over a tunnel frame, and each on an empty stack — each fixture continues past the construct per CLAUDE.md. | **The one behaviour change.** |

S2/S3 order may swap; S4–S6 are independent of each other after S3. The DELIVER roadmap
(`deliver/roadmap.json`, approved 2026-11-17) runs them as nine linear steps: 01-01 S0,
01-02 S1, 02-01 S2, 02-02 S3, 02-03 S4a, 02-04 S4b, 02-05 S5, 02-06 S6, 03-01 S7.

---

## Wave: DESIGN / [REF] Component Decomposition

| Component | Path | Change |
|---|---|---|
| `ContainerPath`, `PathReference`, `PathComponent` | `Sources/SwiftInkRuntime/Decoder/ContainerPath.swift` | CREATE NEW |
| `ContainerPathResolver` | `Sources/SwiftInkRuntime/Engine/ContainerPathResolver.swift` | CREATE NEW (extracted from `InkEngine`) |
| `CallStackElement`, `CallKind` | `Sources/SwiftInkRuntime/Engine/CallStack.swift` | CREATE NEW |
| `NodeKind` (+ `DivertTarget`) | `Sources/SwiftInkRuntime/Decoder/NodeKind.swift` | EXTEND (typed payloads, `.functionCall`) |
| `InkDecoder.classifyDict` | `Sources/SwiftInkRuntime/Decoder/InkDecoder.swift` | EXTEND (parse paths once) |
| `InkEngine` | `Sources/SwiftInkRuntime/Engine/InkEngine.swift` | EXTEND (typed; helpers move out; typed pops) |
| `StoryState`, `StoryPointer`, `ContainerStackFrame`, `ChoiceData` | `Sources/SwiftInkRuntime/Engine/StoryState.swift` | EXTEND (typed fields, legacy wire) |
| `TreeWalker` | `Sources/SwiftInkRuntime/Engine/TreeWalker.swift` | EXTEND (typed payloads) |
| `ExpressionLowering`, `WeaveEmitter`, `ConditionalEmitter`, `VariableTextEmitter`, `RuntimeObjectEmitter` | `Sources/SwiftInkRuntime/Compiler/Codegen/` | EXTEND (emit typed paths / `.functionCall`) |
| `RuntimePathReconciler` | `Sources/SwiftInkRuntime/Compiler/Codegen/RuntimePathReconciler.swift` | EXTEND (typed keys; prefix filter → pattern match) |
| `JSONEmitter`, `Story` facade | `Compiler/Codegen/JSONEmitter.swift`, `Facade/Story.swift` | NO CHANGE |
| `TestPaths` hand port | `scripts/conformance/overrides/TestPaths.swift` | CREATE NEW |
| Golden legacy saves | `Tests/SwiftInkRuntimeTests/Fixtures/` | CREATE NEW (test data) |

## Wave: DESIGN / [REF] Driving Ports

Unchanged public surface: `StoryBlueprint(json:)`, `InkCompiler.compile(source:)`,
`Story.continue()`, `chooseChoice(at:)`, `saveState()`, `restoreState(_:)`,
`moveToKnot(_:stitch:)`, `visitCount(forKnot:)`. **Observable change (S7 only)**:
`Story.currentErrors` reports a mismatched or empty tunnel/function pop and the story
stops (`canContinue == false`) instead of walking on.

## Wave: DESIGN / [REF] Driven Ports & Adapters

| Driven port (substrate) | Adapter | Earned-Trust probe |
|---|---|---|
| Ink-JSON path strings (inklecate) | `InkDecoder` → `PathReference(parsing:)` | Parse never fails (C# semantics: every string is a path; `""` = root), so no new failure mode. Extend the `InkDecoder.probe()` fixture with a relative `.^` path, an `f()` call and a `->t->`, asserting they decode to the typed cases. |
| Persisted saves (older builds, in the wild) | `StoryState` / `CallStackElement` / `ContainerPath` `Codable` | S0 golden legacy saves restore and continue identically; a typed state re-encodes to JSON structurally equal to the golden file (rollback-safety). |
| Behavioural truth | inklecate oracle fixtures + upstream conformance suite | Full suite green per slice; S7 ATs pin the reference refusal. |

## Wave: DESIGN / [REF] Technology Choices

No new dependency. Swift value types (`enum`/`struct`, synthesised `Hashable`), hand-written
`Codable` (Foundation, already used). Enforcement in scope: Swift exhaustiveness on
`NodeKind`/`DivertTarget`/`CallKind`, R2 access control, the existing R1/R3/R5 SwiftLint
rules, and the `parse(description) == self` round-trip test. The symbol-level boundary rule
is a follow-up (below).

## Wave: DESIGN / [REF] Decisions Table

| DDD | Decision | ADR | Status |
|---|---|---|---|
| D1 | `ContainerPath` (absolute) + `PathReference` (absolute \| relative) + `PathComponent`, in `Decoder/` | ADR-016 | Accepted 2026-11-17 |
| D2 | `CallStackElement{kind,returnPath,returnIndex}`; wrong-kind pop → `currentErrors` (exact C# message) + end flow | ADR-017 | Accepted 2026-11-17 |
| D2-scope | Empty-stack `->->` / `~ return` get the same refusal | ADR-017 | Accepted 2026-11-17 |
| D3 | `NodeKind.functionCall(target:)`; `DivertTarget = path \| variable` replaces `isVariable` | ADR-016 | Accepted 2026-11-17 |
| D4 | Typed in memory, byte-identical saved strings, no version field; existing saves keep restoring | ADR-018 | Accepted 2026-11-17 |
| D5 | Stateless `ContainerPathResolver` in `Engine/`; stack mutation stays in `InkEngine` | — (feature-local) | Accepted 2026-11-17 |
| D6 | Slices S0–S7; S7 the only behaviour change | — | Accepted 2026-11-17 |
| D7 | Runtime errors live in memory only (not in `StoryState`, never saved); `restoreState` and `moveToKnot` clear them | ADR-017 | Accepted 2026-11-17 |
| D8 | No DISTILL wave: S0 characterization tests (green from the start), S1 `TestPaths` port, and S7 ATs are written inside their DELIVER steps | — | Accepted 2026-11-17 |

## Wave: DESIGN / [REF] Reuse Analysis

Contract shape · universe per principle 12.

| Existing component | File | Overlap | Decision | Contract shape · universe | Justification |
|---|---|---|---|---|---|
| InkEngine path helpers (`pathComponents`, `parseRelativePath`, `navigate`, `descend`, `navigateWithActualPath`, `navigateAbsolute`, `absolutePath`, `resolveToAbsoluteComponents`, `resolveAnchor`, `resolveReadCountKey`) | `Engine/InkEngine.swift:690-914` | All path navigation | **EXTEND by extraction** into `ContainerPathResolver` | pure-function · reads `root` + a passed-in current path; returns paths/nodes | Same logic moved, not rewritten; becomes testable without an engine. |
| InkEngine stack installers (`installDestinationFrame`, `applyDivert` family, `rebuildStackForParentPath`, `rebuildFullStack`) | `Engine/InkEngine.swift:739-1015` | Stack mutation | **EXTEND** (stay; typed) | bounded-change · universe `containerStack` + `state.pointer` | Mutation stays with the stack's owner (D5). |
| Return-address builders/parsers (`buildTunnelReturnAddress`, `buildFunctionReturnAddress`, `applyFunctionReturn` string parsing, `hasPrefix("fnret:")`) | `Engine/InkEngine.swift:270,341,606-682` | Return addresses | **REPLACE** by `CallStackElement` (CREATE NEW) | pure value · Codable to legacy strings | No existing type carries a kind + pointer; the string *is* the type today. |
| `StoryState` + nested types | `Engine/StoryState.swift` | Persisted paths, return stack, visit counts | **EXTEND** | bounded-change · universe: field types + `Codable` mapping; wire unchanged | Hand-written `Codable` already exists; extend it. |
| `InkDecoder.classifyDict` | `Decoder/InkDecoder.swift:155-197` | JSON → node | **EXTEND** | pure-function · JSON value → `NodeKind` | The single parse site for paths. |
| `NodeKind` | `Decoder/NodeKind.swift` | Node payloads | **EXTEND** | pure value | Typed payloads + one case; R2 unchanged. |
| `TreeWalker` (`resolveReadCountPath`, `handleDivert`) | `Engine/TreeWalker.swift:232-237,355-366` | Second relative-path rule; pointer write | **EXTEND** (typed); deletion checked in S2 | bounded-change · `state.evalStack`/`pointer` | See Follow-ups. |
| `ExpressionLowering.functionCallTargetPrefix` | `Compiler/Codegen/ExpressionLowering.swift:19,110` | `f():` spelling #2 | **EXTEND** (emit `.functionCall`; delete constant) | pure-function · AST → `[NodeKind]` | Prefix existed only for the engine's string check. |
| `RuntimePathReconciler` | `Compiler/Codegen/RuntimePathReconciler.swift` | Path keys, `f():` filter, dotted suffix matching | **EXTEND** | pure-function · tree → rewritten tree | Compares `ContainerPath` components; filter becomes a pattern match. |
| `JSONEmitter` | `Compiler/Codegen/JSONEmitter.swift` | Secondary JSON sink | **NO CHANGE** | pure-function | Does not serialise diverts. |
| `ContainerNode` | `Decoder/ContainerNode.swift` | Tree navigated by paths | **REUSE AS-IS** | pure value | `children`/`namedContent` are what `.index`/`.name` address. |
| Conformance harness | `Tests/.../Conformance/ConformanceSupport.swift` | Reads `story.currentErrors` | **REUSE AS-IS** | test utility | S7 errors visible to `hadError` unchanged. |

Outcome Collision Check: skipped — `docs/product/outcomes/registry.yaml` does not exist.

## Wave: DESIGN / [REF] Open Questions

None. The last one, runtime-error lifetime, is decided as D7: errors in memory only,
cleared by `restoreState` and `moveToKnot`. A story has no way to recover from a runtime
error, so a saved error would only persist an unrecoverable state; errors are not meant as
a diagnostics record. Both calls start from a different position, so the old error no
longer describes the story.

The DISTILL wave is skipped (D8): #25 adds no behaviour beyond S7. The existing suite
(inklecate oracle fixtures plus the upstream conformance suite) guards S1–S6; as an extra
check, each behaviour-preserving slice compares the failure messages of
`INKSWIFT_CONFORMANCE_BACKLOG=1 swift test --filter UpstreamConformance` before and after,
which must not change.

### Follow-ups — out of scope for #25

- **Suspected tunnel-return-into-container bug (unconfirmed)**: a tunnel return `"path.N"`
  is resolved through `applyDivert`; when `children[N]` is itself a container,
  `applyAbsoluteDivert` enters that child with a single-frame stack, dropping ancestor
  frames, where the reference resumes `Pointer(container, N)` with the call stack intact.
  S6 preserves today's resolution. Confirm with a fixture (container right after
  `-> tunnel ->`, content after it) and file a separate issue.
- **TreeWalker dead-code check (during S2)**: `TreeWalker.resolveReadCountPath` looks
  unreachable during play (`InkEngine.executeNextChild` intercepts `.readCount` first) and uses
  a different, named-only caret rule; `TreeWalker.handleDivert`'s `pointer.containerPath`
  write is overwritten before any reader. Try deleting both (CLAUDE.md); if the suite stays
  green, delete instead of typing them, otherwise type them and record why.
- **Symbol-level boundary rule**: R1/R5 regexes match only `import Engine` lines, which never
  occur in one module. A `.swiftlint.yml` rule `r1_r5_no_engine_symbols` over `Decoder/` +
  `Compiler/` (matching `InkEngine`, `StoryState`, `TreeWalker`, `ContainerPathResolver`,
  `CallStackElement`) would close the gap.
- **`ChoiceFlags` placement**: defined in `Engine/`, referenced by `Decoder/NodeKind` — move
  to `Decoder/` so the rule above can cover it.
- **Divert-target values in `InkValue`** (`.pushDivertTarget` pushes `.string(path)`; C# has
  `DivertTargetValue`): typing them changes the `variablesState` wire format. The
  variable-divert site stays the one runtime parse of a path string.
- **5B / 5C extractions** (a `ContainerStack` type; `ContainerNode` navigation shared with the
  compiler) and folding `callFrameVariables`/`functionRootDepths` into `CallStackElement`.

## Wave: DESIGN / [REF] Wave decisions summary

### Key Decisions

- [D1] `ContainerPath` (absolute) + `PathReference` (absolute | relative with parent-step
  count) + `PathComponent` (index | name) in `Decoder/`; never-failing parse;
  `description` round-trips today's dotted strings. (source: ADR-016; C# `Path.cs`)
- [D2] `CallStackElement { kind: tunnel|function, returnPath, returnIndex }`; wrong-kind or
  empty-stack pop → refuse, exact C# message in `currentErrors`, end the flow; no public API
  change. (source: ADR-017; C# `CallStack.cs:326-345`, `Story.cs` ~1255-1297; upstream issue
  search, inkle/ink#466)
- [D3] `NodeKind.functionCall(target:)`; `DivertTarget = path | variable` replaces
  `isVariable`; `f():` deleted everywhere. (source: ADR-016; ADR-006 Option A; `JSONEmitter`)
- [D4] Typed in memory, byte-identical saved strings, no version field; existing saves keep
  restoring; hand-written `Codable` for path-keyed dictionaries. (source: ADR-018; ADR-003;
  `job-state-durability`)
- [D5] Stateless `ContainerPathResolver` in `Engine/`; `InkEngine` keeps stack mutation.
  (source: this document, D5)
- [D6] Slices S0–S7, trunk-based, S7 the only behaviour change. (source: this document, D6;
  CLAUDE.md trunk-based + `.disabled` AT rules)

### Architecture Summary

- **Pattern**: modular monolith, layered (`Facade/` → `Engine/` → `Decoder/`; `Compiler/` →
  `Decoder/`), unchanged.
- **Paradigm**: object-oriented (CLAUDE.md) — value-type structs/enums; the engine stays the
  stateful owner.
- **Key components**: `ContainerPath`/`PathReference`/`PathComponent` (new, `Decoder/`),
  `ContainerPathResolver` (new, `Engine/`), `CallStackElement`/`CallKind` (new, `Engine/`),
  `NodeKind` + `DivertTarget` (extended), `InkEngine`, `StoryState`, `InkDecoder`, compiler
  codegen (extended).

### Reuse Analysis

| Existing component | Decision |
|---|---|
| `InkEngine` path helpers | EXTEND by extraction → `ContainerPathResolver` |
| `InkEngine` stack installers | EXTEND (stay, typed) |
| Return-address string builders/parsers | REPLACE by `CallStackElement` (CREATE NEW) |
| `StoryState` + nested types | EXTEND (typed fields, legacy wire) |
| `InkDecoder.classifyDict`, `NodeKind` | EXTEND |
| `TreeWalker` | EXTEND (dead-code deletion checked in S2) |
| `ExpressionLowering`, emitters, `RuntimePathReconciler` | EXTEND |
| `JSONEmitter`, `Story` facade, `ContainerNode`, conformance harness | NO CHANGE / REUSE AS-IS |

### Technology Stack

Swift 5.6 tools, Foundation `Codable` (`JSONEncoder`/`JSONDecoder`, already used for
`StoryState`), SwiftLint (existing R1/R3/R5). No new dependency.

### Constraints Established

- Paths parsed once, in `InkDecoder`; the `.ink.json` boundary stays string-based.
- Save wire format byte-identical; existing saves restore; no version field.
- No `CodingKeyRepresentable` dictionary encoding (deployment targets macOS 10.15 / iOS 13).
- Every slice behaviour-preserving except S7. Per D8 there is no DISTILL wave: S7's ATs are
  written inside the S7 step (red → green → commit), so no AT is ever `.disabled`; zero
  `.disabled` ATs at finalize.
- Runtime error text = the exact C# message.

### Upstream Changes

None — no DISCUSS wave existed; requirements came from issue #25.
