# ADR-011: Weave-Label Read-Count Addressing

## Status

Accepted (DESIGN — native-ink-compiler weave-label slice, 2026-06-15). **Option B CHOSEN**
(incremental label→path table via extended `LoweringContext` + discovery pre-pass), explicitly
grounded in the original inklecate C# compiler's three-phase weave-naming algorithm (see "Evidence
from the original inklecate compiler" below). Governing heuristic: *when in doubt, follow the
original.* Implementation pending DELIVER.

## Context

The native compiler (`Sources/SwiftInkRuntime/Compiler/`) cannot compile a **dotted
read-count reference to a named weave label** inside a condition, e.g.

```ink
{harris_demands_component.cant_talk_right: helplessly}
```

This is the sole remaining blocker for the flagship `TheIntercept.ink` full
native-compile end-to-end oracle test (choice script `[0,2,1,0,0,1,2,0,1,0]`,
`native == oracle`). The `compiler-variable-text` slice-04 honest RED falsified the
"line-86 variable-text was the only blocker" descope premise and surfaced this as a
distinct **weave-label addressing** concern, descoped (user-approved 2026-06-15) to
this feature. Two `.disabled` acceptance tests in
`Tests/SwiftInkRuntimeTests/Acceptance/Compiler_S4_CeilingTests.swift` re-enable when
this lands:

- `The Intercept compiles natively and plays identical to the inklecate oracle` (e2e), and
- `a dotted read-count reference to a named stitch lowers to a read-count node` (RED pin).

### What is broken today

The step-06-01 investigation (commit `aa72e14`) established the precise gap. A dotted
read-count subject is **rejected at parse time** (`.unexpectedToken("waiting.guard_post")`),
and even past the parser the emitter is wrong:

1. **Parser** — choice lines do not parse a `(label)` weave-label nor a `{condition}`
   guard; the AST `choice` case carries neither. (Gathers already parse `(label)`.)
2. **Container keying** — `WeaveEmitter` keys choice outcome containers positionally
   (`c-N`); a labelled choice is addressable by neither a divert target nor a read count.
3. **Count-visits flag** — no compiler-emitted container sets the runtime's
   `0x1` CountVisits flag, so a resolved read count would always evaluate `0`.
4. **Name→path resolution** — no table maps a source-level dotted name
   (`knot.label`) to its labelled container's emitted absolute path, so
   `lowerExpression`'s `.variableReference` case emits the runtime-unresolvable
   `.variableReference("harris_demands_component.cant_talk_right")` instead of a
   `.readCount(resolvedPath)`.

### What is already true (do NOT rebuild)

- **The runtime side is fully implemented.** `containerFlagCountVisits = 0x1`
  (`Engine/InkEngine.swift:6`) makes the engine track visits of any flagged container
  — including **choice body containers** (`InkEngine.swift:1043-1045`) — into
  `state.visitCounts[absolutePath]`. `NodeKind.readCount(String)` (`Decoder/NodeKind.swift:20`)
  resolves an **absolute** key as-is against `visitCounts` (`InkEngine.swift:794-795`,
  `TreeWalker.swift:86-90`). The `CNT?` decoder path
  (`InkDecoder.swift:174-175`) is the JSON counterpart. **No runtime/Engine/Decoder
  change is in scope** (and is forbidden by the R1/R3/R5 boundary).
- **`WeaveEmitter` already exists and ships** (`Compiler/Codegen/WeaveEmitter.swift`,
  the former "deferred WeaveResolver" — renamed and delivered in DELIVER S3, 4/4
  fixtures oracle-green). It already owns the `c-N`/`g-N` namespace, already keys
  **gathers** by their `(label)`, builds absolute-qualified paths from root, and
  resolves loose ends. It is the natural home for label-keyed choice containers and
  the count-visits flag.
- **Correctness is Level-1 execution-equivalence** (D5): native playback ==
  committed inklecate oracle along the fixed choice script. The compiler emits its
  OWN resolved path — it need NOT reproduce inklecate's literal container IDs
  (oracle path `harris_demands_component.0.g-1.c-14` is informational only).

### Evidence from the original inklecate compiler

The chosen approach (Option B) follows how the original inkle/ink C# compiler
(`/Users/Maarten.Engels/Downloads/ink`) resolves weave-label read-count references.
The original uses a **three-phase** algorithm (driver: `compiler/ParsedHierarchy/Story.cs`
`ExportRuntime`):

1. **Early name registration** — `Weave.ResolveWeavePointNaming()`
   (`compiler/ParsedHierarchy/Weave.cs:81-100`) runs **before** codegen and registers
   **only labelled** gathers/choices into a `name → weave-point` dictionary
   (`_namedWeavePoints`). It iterates `FindAll<IWeavePoint>(w => !IsNullOrEmpty(w.name))`
   and also detects duplicate-label collisions. Unlabelled weave points get auto-names
   (`g-N`, `c-N`) but are **NOT addressable by name**. This is the forward-reference-tolerant
   name pass.
2. **Generate the full runtime container tree** — the `GenerateRuntimeObject` cascade
   assigns container names so each target's path becomes available. Choice inner
   containers are always named `c-{count}` (`Weave.cs:297-300`); unlabelled gathers
   `g-{count}` (`Weave.cs:222-226`); a **labelled** gather/choice ALSO carries the label
   as its runtime container name (`Gather.cs:21-24`). Paths are therefore fully computed
   and cached as each container's `runtimePath`.
3. **Late reference resolution** — `VariableReference.ResolveReferences()`
   (`compiler/ParsedHierarchy/VariableReference.cs:87-142`) resolves the dotted path
   against the name table, walking up the lexical-scope parent chain
   (`Path.ResolveFromContext` / `ResolveBaseTarget`, `Path.cs:83-134`). On a hit it
   **READS the target's already-computed `runtimePath`** (`VariableReference.cs:111`) — it
   never re-derives a path — and patches it into `pathForCount`, setting `name = null`.
   JSON shape is `{"CNT?": "<path>"}` (`JsonSerialisation.cs:199-218`). On a **miss** for a
   single-component name it falls through to ordinary variable resolution
   (`VariableReference.cs:129-141`).

Two specifics of the original directly shape this design:

- **Labelled-only addressability** — the name table holds ONLY labelled weave points
  (`Weave.cs:83` filters on a non-empty `name`); unlabelled containers (`g-N`/`c-N`) are
  not name-addressable. Our `weaveLabelPaths` table mirrors this: it contains label entries
  only.
- **Retroactive / targeted count-visits flag** — the `#f` CountVisits (`0x1`) flag is set
  on a container **only when a read-count reference actually resolves to it**
  (`VariableReference.cs:101`: `targetForCount.containerForCounting.visitsShouldBeCounted = true`),
  NOT eagerly on every labelled container. (The global `countAllVisits` option flags
  everything, but it is OFF for normal compiles, so the committed oracle carries the flag
  only on *referenced* labels.) Therefore our discovery pre-pass must collect the **SET of
  labels that are read-count-referenced**, and `WeaveEmitter` sets the CountVisits flag on
  exactly those containers (see WL-D4, refined below).

**How Option B maps to the original.** Our emitter lowers expressions inline
(`ConditionalEmitter` → `lowerExpression`), not in a separate post-pass, so the
`label → path` mapping must be available at lowering time → hence a **table**. `WeaveEmitter`
ALREADY computes each labelled container's absolute path during emission, so Option B
captures that path into the table — this is precisely the original's "read the cached
`runtimePath`, never re-derive." The **discovery pre-pass** plays the role of the original's
early `ResolveWeavePointNaming` (forward-reference tolerance). Option B is inklecate's
three-phase strategy (`ResolveWeavePointNaming` → `GenerateRuntimeObject` →
`ResolveReferences`) adapted to our inline-lowering architecture, producing identical oracle
output. Option A (re-walk the emitted tree and re-derive paths) is the one thing the original
deliberately avoids, so it is correctly rejected.

## Decision

Build weave-label read-count addressing as a **minimal extension of the existing
emitter pipeline**, NOT a new component, following the original inklecate three-phase
algorithm above (Option B). Five coordinated changes:

1. **Parser (EXTEND `InkParser` + `CompilerAST`)** — parse a leading `(label)` on a
   choice line (mirroring the existing `splitGatherLabel` / `splitBracketedLabel`
   helper, now applied with `(`/`)` to choices) and a `{condition}` guard on a
   choice line. Add `weaveLabel: String?` and `condition: InkExpression?` to the AST
   `choice` case.
2. **Label-keyed choice containers (EXTEND `WeaveEmitter`)** — when a choice carries
   a `(label)`, key its outcome container by that label instead of `c-N`
   (exactly as `gatherKey` already does for gathers: `label ?? "c-N"`). The label
   becomes the addressable name segment in the absolute path.
3. **Count-visits flagging (EXTEND `WeaveEmitter`)** — set the container `flags` to
   `0x1` (CountVisits) on exactly the labelled containers that are **read-count-referenced**
   (the SET collected by the discovery pre-pass), so the runtime tracks their visit
   counts. This matches the original (`VariableReference.cs:101` flags a container only
   when a reference resolves to it; `countAllVisits` is OFF for normal compiles) and is
   leaner and oracle-correct than flagging every labelled container. Today every emitted
   weave container uses `flags: 0`.
4. **Name→path resolution table (EXTEND `LoweringContext`)** — register a
   `weaveLabelPaths: [String: [String]]` map (source dotted name →
   absolute compiled path) during weave lowering, threaded through the existing
   `LoweringContext` that already carries the CONST and function tables.
5. **`.readCount` emission (EXTEND `RuntimeObjectEmitter.lowerExpression`)** — in the
   `.variableReference(name)` case, if `name` (or its dotted form) resolves in
   `weaveLabelPaths`, emit `.readCount(resolvedAbsolutePath)` instead of
   `.variableReference(name)`. Single dotted identifiers that name a known label
   resolve; everything else keeps today's behaviour.

The driving port is unchanged: `InkCompiler.compile(source:) -> StoryBlueprint`. No
new driven port. No new dependency. Object-oriented/imperative paradigm, matching the
existing `WeaveEmitter`/`ConditionalEmitter` value-type-with-methods style.

The name→path table is built by a **two-phase walk inside the existing
`WeaveResolver.resolve` recursion** (the resolution-table option, below), mirroring the
original's phase-1/phase-3 split: pass 1 (the discovery pre-pass, = inklecate's
`ResolveWeavePointNaming`) records every labelled container's absolute path into the
`LoweringContext` table AND collects the SET of labels that are read-count-referenced;
pass 2 (expression lowering, = inklecate's `ResolveReferences`) reads the table to emit
`.readCount(path)`, and `WeaveEmitter` sets the `0x1` CountVisits flag on exactly the
referenced containers from that set. Because `resolve` already computes every container's
absolute `keyPrefix`, recording the label→path entry is a near-zero-cost addition at the
existing keying site — no separate post-order tree walk is introduced, and (per the
original) no path is ever re-derived.

## Alternatives Considered

### Option A — Post-lowering pass over the emitted `ContainerNode` tree

After the whole tree is emitted, walk it to discover labelled containers, build the
name→path table, then re-walk to rewrite any `.variableReference(dotted)` into
`.readCount(path)`.

- **Pro**: fully decoupled from the emitters; one isolated pass.
- **Con (rejected)**: requires **re-deriving absolute paths the resolver *already*
  computed** — and re-deriving paths is the one thing the original inklecate compiler
  deliberately avoids (it reads the cached `runtimePath`, `VariableReference.cs:111`).
  Duplicated path arithmetic is the highest correctness risk for deeply nested containers,
  exactly the `harris_demands_component.c-0.g-1.c-14` case. Also needs a tree-mutation pass
  over an immutable `ContainerNode` (rebuild-on-rewrite), and a heuristic to distinguish a
  dotted read-count from a legitimate dotted variable after the fact. Two extra traversals
  for data the resolver had in hand.

### Option B — Incremental name→path registration during lowering (CHOSEN)

Register label→absolute-path entries into the `LoweringContext` table *as the
`WeaveResolver` keys each labelled container* (it already holds the `keyPrefix`);
read the table in `lowerExpression` when emitting `.readCount`.

- **Pro**: reuses the resolver's already-correct absolute-path computation (zero
  duplicated path arithmetic — eliminates the nested-container correctness risk);
  one extra dictionary write per labelled container; aligns precisely with the
  established `LoweringContext`-threading pattern (CONST table, function table) and
  the `WeaveEmitter`/`ConditionalEmitter` named-collector idiom; no tree mutation.
- **Con**: a forward-reference ordering concern (an expression may reference a label
  emitted later). Mitigated by a **discovery pre-pass**: walk the parsed
  `[InkStatement]` weave structure to register all labels' paths *before* expression
  lowering runs, so resolution is order-independent. The pre-pass reuses the same
  `WeaveParser` level-partitioning the resolver already performs.

### Option C — A dedicated new `WeaveLabelResolver` component

A standalone component owning label discovery + path resolution as its own concern.

- **Pro**: single-responsibility, independently testable.
- **Con (rejected)**: `WeaveEmitter` *already* owns weave structure, the `c-N`/`g-N`
  namespace, gather-label keying, and absolute-path construction (the original fuses these
  same concerns into `Weave`/`Gather` rather than a separate resolver). A separate resolver
  would either **duplicate that traversal** (Option A's path-re-derivation cost) or **couple
  tightly to** `WeaveEmitter`'s internal `WeaveBlock`/`WeaveResolver` types — re-implementing
  what exists. Per the Reuse Analysis default (EXTEND unless extending is impossible),
  CREATE NEW is unjustified: the extension is ~label-keying + a (targeted) flag + a dictionary
  write inside the component that already does the surrounding work.

## Consequences

### Positive

- Closes the last gap to the flagship `TheIntercept.ink` e2e; both `.disabled` ATs
  re-enable, discharging the consciously-waived "zero `.disabled` at finalize"
  exception from `compiler-variable-text`.
- Zero runtime/Engine/Decoder change — the boundary (R1/R3/R5) holds; the runtime
  read-count machinery is exercised, not extended.
- No new component, no new dependency, no new driven port — the smallest viable diff
  over the existing emitter pipeline.
- Reuses the resolver's proven absolute-path arithmetic, so deeply nested labelled
  containers (the real `TheIntercept` shape) inherit existing correctness.

### Negative / Risks

- **Forward references** require the discovery pre-pass; without it, a label
  referenced before it is lowered would mis-resolve. Mitigation is in the decision
  (pre-pass before expression lowering).
- **Label-vs-variable ambiguity**: a dotted name that is NOT a known weave label must
  still fall through to `.variableReference` (today's behaviour) — the resolver table
  is consulted, and a miss is not an error here (it may be a genuine qualified
  variable the runtime resolves). The RED-pin AT asserts no dotted `.variableReference`
  *for a known label* survives; it does not forbid all dotted variables.
- **Count-visits scope**: flagging `0x1` only on the *read-count-referenced* labelled
  containers (the SET from the discovery pre-pass) keeps the blast radius minimal and
  matches inklecate exactly (`VariableReference.cs:101` flags a container only when a
  reference resolves to it; `countAllVisits` is OFF for normal compiles). Over-flagging
  every labelled container — let alone unlabelled ones — would change visit semantics for
  unrelated read-counts and diverge from the committed oracle — explicitly avoided.

## Architecture Enforcement

Style: Modular monolith — single `Compiler/` layer, ports-and-adapters at the
`InkCompiler.compile` driving port. Language: Swift. Tool: SwiftLint `custom_rules`
(R1/R3/R5, already enforced `--strict` in the pre-commit gate + CI).

Rules that continue to apply (no new rule needed):

- `Compiler/` imports no `Engine/` (R1) — this slice touches only `Compiler/`.
- `Compiler/` performs no `JSONSerialization` (R5) — emission stays in `Decoder/`
  node types via the existing `RuntimeObjectEmitter` path.
- Correctness gate: the execution-equivalence oracle suite (the two re-enabled ATs +
  a focused weave-label read-count fixture). Mutation testing is disabled project-wide
  (CLAUDE.md); oracle equivalence + code review + the boundary gates carry test quality.
