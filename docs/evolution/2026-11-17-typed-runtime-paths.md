# Evolution — typed-runtime-paths

**Status**: COMPLETE — container paths, relative paths, return addresses and function-call diverts in `SwiftInkRuntime` are value types mirroring the C# reference, parsed once at the JSON boundary, emitted typed by the native compiler and persisted in the **unchanged** save format. Nine steps delivered on `main`; one deliberate behaviour change (type-checked tunnel/function pops).
**Date**: 2026-11-17
**Issue**: #25
**Predecessor**: `docs/evolution/2026-06-06-tier3-conditionals-and-tunnels.md` — introduced the string return addresses (ADR-004) this feature replaces.

Internal refactor driven by an issue, not a user story: no DISCUSS wave, no DISTILL wave (D8). Waves ran DESIGN → DELIVER → finalize. The durable lesson: **checking each InkSwift-only mechanism against the C# source during a behaviour-preserving refactor removed code the oracle could never have flagged** — three dead or counterpart-less mechanisms went, with the suite unchanged.

---

## Feature Summary

Before #25 the runtime carried paths as dotted strings: `"knot.0.c-1"` for container paths, `".^.^.x"` for relative references, `"path.N"` and `"fnret:path|N"` for return addresses on the call stack, and a `"f():name"` prefix on `.divert` to mark a function call. Every consumer re-parsed them (`hasPrefix(".")`, `hasPrefix("fnret:")`, `split(".")`), CodeScene flagged the Primitive Obsession in `InkEngine.swift`, and a relative path could reach a state key. A mismatched pop (`->->` over a function frame, `~ return` over a tunnel frame) was silently tolerated, where the reference reports an error.

After #25:

- `ContainerPath` / `PathReference` / `PathComponent` (C# `Path`) — total parse with C# `Path.componentsString` semantics; `description` reproduces every legacy string.
- `ContainerPathResolver` — stateless navigation over the immutable root, testable without an engine.
- `NodeKind` payloads typed; `DivertTarget = path | variable` replaces `isVariable`; `NodeKind.functionCall(target:)` replaces the `f():` prefix (C# `Divert.pushesToStack`).
- `CallStackElement { kind: tunnel | function, returnPath, returnIndex }` on the return stack (C# `CallStack.Element` / `PushPopType`), with kind-checked `pop(_:)` / `canPop(_:)`.
- Saves are byte-identical to the previous build in both directions.

### Components Shipped

| Component | Path | Role | Decision |
|---|---|---|---|
| `ContainerPath`, `PathReference`, `PathComponent` (+ `root`, `appending(_:)`, `parent`, `isStrictPrefix(of:)`, `isAnchor`) | `Decoder/ContainerPath.swift` | Typed path values in the lowest layer | **CREATE NEW** (D1, ADR-016) |
| `ContainerPathResolver` | `Engine/ContainerPathResolver.swift` | Pure navigation: absolute, caret-relative, knot-namespace, `$`-anchor, read-count keys, ancestor chain | **CREATE NEW** by extraction (D5) |
| `CallStackElement`, `CallKind` | `Engine/CallStack.swift` | Typed return stack; legacy-string `Codable` | **CREATE NEW** (D2, ADR-017/018) |
| `NodeKind` + `DivertTarget`, `.functionCall` | `Decoder/NodeKind.swift` | Typed payloads | **EXTEND** (D3) |
| `InkDecoder` | `Decoder/InkDecoder.swift` | Parses each path once; `{"f()": path}` → `.functionCall`; probe extended | **EXTEND** |
| `InkEngine`, `StoryState`, `TreeWalker` | `Engine/` | Typed internals; type-checked pops; `currentErrors` | **EXTEND** |
| Compiler codegen (`ExpressionLowering`, `WeaveEmitter`, `ConditionalEmitter`, `VariableTextEmitter`, `RuntimeObjectEmitter`, `RuntimePathReconciler`) | `Compiler/Codegen/` | Emit and compare typed paths | **EXTEND** |

No public API change, no new dependency.

---

## Key Decisions

| ID | Decision | ADR |
|---|---|---|
| D1 | `ContainerPath` (absolute) + `PathReference` (absolute \| relative with raw caret count) + `PathComponent` (index \| name), in `Decoder/`; never-failing parse; structural equality (`knot.0` ≠ `knot.c-0`) | [ADR-016](../product/architecture/adr-016-typed-container-path.md) |
| D2 | `CallStackElement`; a wrong-kind **or empty-stack** pop is refused with the exact C# message and ends the flow | [ADR-017](../product/architecture/adr-017-typed-call-stack-and-pop-check.md) |
| D3 | `NodeKind.functionCall(target:)`; `DivertTarget` replaces `isVariable`; `f():` deleted | [ADR-016](../product/architecture/adr-016-typed-container-path.md) |
| D4 | Typed in memory, byte-identical saved strings, no version field | [ADR-018](../product/architecture/adr-018-save-format-compat-typed-paths.md) |
| D5 | Stateless `ContainerPathResolver` in `Engine/`; `containerStack` mutation stays in `InkEngine` | feature-delta |
| D6 | Slices S0–S7, trunk-based; S7 the only behaviour change | feature-delta |
| D7 | Runtime errors live in memory only, never saved; `restoreState` and `moveToKnot` clear them | [ADR-017](../product/architecture/adr-017-typed-call-stack-and-pop-check.md) |
| D8 | No DISTILL wave: S0 characterization tests, the S1 `TestPaths` port and the S7 ATs are written inside their DELIVER steps | feature-delta |

---

## Work Completed

| Step | Slice | Commit | What |
|---|---|---|---|
| 01-01 | S0 | `215d178` | Four golden saves captured from unmodified `Story.saveState()` at `e7d0830` (mid-tunnel, once-only chosen, visit counts, choice point); restore-and-continue and canonical re-save tests. Test-only. Found the frame-less-save normalisation (ADR-018, `2525406`). |
| 01-02 | S1 | `67dc90f` | Path value types, round-trip over ~680 path strings walked from the committed fixtures plus 16 edge cases; upstream `TestPaths` hand-ported and removed from `known-failures.json`. |
| — | — | `a75919f` | Conformance character-range ports name the range instead of a multi-thousand-character identifier, making the backlog failure list deterministic. |
| 02-01 | S2 | `2698487` | `ContainerPathResolver` extracted from `InkEngine`; dead `TreeWalker` code deleted. |
| 02-02 | S3 | `3a7f9f3` | Frames, pointer, `visitCounts`, `chosenChoiceTargets` typed; hand-written `Codable` keeps the wire (description-keyed dictionaries, sorted choice targets). |
| — | — | `b5f7eeb` | Linux portability fix in `ContainerPathTests` (see Quality). |
| 02-03 | S4a | `f34cae6` | `readCount`, `choicePoint`, `tunnelDivert`, `pushDivertTarget` payloads → `PathReference`; two resolver fallbacks deleted. |
| 02-04 | S4b | `e7ae82e` | `.divert(target: DivertTarget, isConditional:)`; conditional variable divert aligned with `Story.cs`. |
| 02-05 | S5 | `4a5b397` | `NodeKind.functionCall`; every `f():` spelling deleted. The inklecate JSON key `"f()"` in `InkDecoder` is the only survivor. |
| 02-06 | S6 | `0f8e555` | `CallStackElement` on `returnStack`; `buildTunnelReturnAddress`, `buildFunctionReturnAddress` and every `hasPrefix("fnret:")` gone. Malformed entries now rejected (ADR-018, `68eb85c`). |
| 03-01 | S7 | `b071056` | Type-checked pops (below). |
| review | — | `3c0607c` | Review findings M3 (stale comments) and M5 (path helpers moved next to the types). |
| docs | — | `8bab3b5` | Migration guide, parity reference, known-gaps, `brief.md` component diagram, ADR-004 marked partly superseded. |

Suite grew from 780 to 800 tests over the feature. Every step logged RED → GREEN → COMMIT in `execution-log.json`; `des-verify-integrity` passes.

---

## The Behaviour Change (S7)

`->->` pops only a tunnel element, `~ return` only a function element. A pop whose top element is the other kind, or whose stack is empty, is refused. The exact C# message (`Story.cs` ~1275-1288) is appended to `Story.currentErrors`:

- `Found tunnel onwards statement (->->), when expected function return statement (~ return)` (and the reverse)
- `Found … , when expected end of flow (-> END or choice)` for an empty stack

The flow ends as C# `AddError` → `ForceEnd` does: return stack reset, choices dropped, `isEnded`. Errors live in `InkEngine` memory only (D7). They are never in `StoryState` or a save, and `restoreState` / `moveToKnot` clear them. InkSwift reports the bare message; inkjs prefixes `RUNTIME ERROR: (<pointer>): `.

Function-body exhaustion over a tunnel frame: `Story.cs` pops on exhaustion only when `CanPop(Function)`, so the flow ends with the tunnel frame unconsumed. InkSwift already did this; the AT now pins it. inkjs also reports the "unexpectedly reached end of content" error. That check family is outside ADR-017 and not implemented (#28).

Fixtures: five inklecate-compiled `pop-*.ink` stories. Each has content after the construct that must not play. inklecate rejects choices and plain diverts inside functions, so functions are reached by variable divert and the continuation choice sits in the caller.

---

## Alignment With the C# Source

Each behaviour-preserving step checked the mechanisms it touched against the reference (CLAUDE.md "The oracle is necessary, not sufficient"):

- **02-01** — `TreeWalker.resolveReadCountPath` (unreachable: `InkEngine` intercepts `.readCount` first, and it used a second, named-only caret rule) and `handleDivert`'s pointer write (overwritten before any read) deleted. Only two `TreeWalkerTests` asserting the removed write failed; they went with it.
- **02-03** — two resolver fallbacks with no C# counterpart deleted:
  - knot-namespace `"0"` fallback in `destination(of:from:)`. `Container.cs` `ContentAtPath` follows only an index or a named child.
  - read-count concatenation fallback in `readCountKey(for:from:)`. `Story.cs` reads `CNT?` via `ResolvePath(...).container`. A missing relative destination now yields count 0, like an absolute key to a nonexistent path.

  Suite and backlog were unchanged; only our own tests asserting the fallbacks were removed. The `$`-anchor resume at `i+1` was **kept**, with its `Story.cs` counterpart cited in code.
- **02-04** — a conditional *variable* divert used to apply the variable name as a path. It now checks the condition first and then resolves the variable, as `Story.cs` does (`isConditional`, then `hasVariableTarget`). No fixture or conformance case contains that combination.

---

## Save-Format Exceptions (ADR-018)

Byte identity holds in both directions, with two recorded exceptions:

1. **Frame-less-save normalisation** (found in 01-01, accepted by the maintainer). A save with `stackFrames: []` (top-level choice point) gets one frame synthesised from `pointer` on restore, and the next save writes it out. This is existing behaviour that plays identically, every build reads both forms, and it is a fixed point after one round. The goldens pin it.
2. **Malformed return-stack entries are rejected** (02-06). An entry fitting neither `"<path>.<index>"` nor `"fnret:<path>|<index>"` now throws on restore instead of being tolerated. Only a two-day window on `main` in June 2026 (`30fe0ec`–`ea11694`) wrote such entries, and no release tag contains it.

---

## Quality State at Finalize

- **Suite**: 800 tests green on macOS (pre-commit gate: SwiftLint `--strict` + `swift test`); Linux CI green after `b5f7eeb`.
- **Conformance backlog guard**: on every behaviour-preserving step, the failure list from `INKSWIFT_CONFORMANCE_BACKLOG=1 swift test --no-parallel --filter UpstreamConformance` was diffed against a baseline. The diff was empty each time (360 lines), apart from 01-02, where `TestPaths` left the backlog as intended.
- **Mutation testing**: automated mutation testing is disabled project-wide (CLAUDE.md). Instead, each step ran 3–6 manual mutations, each applied alone against the full suite and reverted, and reported them in its commit message. Survivors were killed with a new test (02-02 M5, 02-03 M2/M5) or recorded as equivalent with an argument (01-01 M4, 02-03 M3/M4, 02-05 M5, 02-06 M4). 03-01: 6/6 caught.
- **S0 goldens have teeth**: they caught mutations in 01-01 (visit-count decode, dropped choice target, return-stack mis-parse, dropped continuation-root flag), 02-02, 02-04 (variable divert decoded as path; dropped `isConditional`) and 02-06 (tunnel return index off by one; kind-blind body exhaustion).
- **CodeScene**: `InkEngine.swift` 9.38 → **9.84**. New files (`ContainerPath`, `ContainerPathResolver`, `CallStack`) **10.0**. `StoryState` and `RuntimePathReconciler` stay at 10.0. No changed file dropped below its baseline (`InkDecoder` 8.04, `TreeWalker` 7.19 and `VariableTextEmitter` 9.38 unchanged, with pre-existing findings).
- **Invariants**: zero `.disabled` ATs (D8: ATs were written green-or-red inside their steps, never disabled). No `f():` literal in `Sources/`.
- **Linux**: `ContainerPathTests` used `Bundle.urls(forResourcesWithExtension:subdirectory:)`, which returns `[NSURL]?` in swift-corelibs-foundation ([swiftlang/swift-corelibs-foundation#5446](https://github.com/swiftlang/swift-corelibs-foundation/issues/5446)), so the whole test target failed to compile on Linux. `b5f7eeb` lists the bundle directory with `FileManager` instead.

---

## Artifact Migration

None needed. ADR-016/017/018 were written directly to `docs/product/architecture/`, and `brief.md` is already the architecture SSOT. The feature workspace has no `discuss/`, `design/` or `distill/` subfolders. `docs/feature/typed-runtime-paths/` (feature-delta, `deliver/roadmap.json`, `deliver/execution-log.json`) stays as delivery history.

---

## Lessons Learned

1. **A behaviour-preserving guard must be deterministic first.** The conformance backlog only worked as a before/after diff once the character-range ports emitted short failure messages (`a75919f`). Long lines were spliced by parallel test output. It also had to run with `--no-parallel`.
2. **Read the source alongside the oracle during refactors.** Three mechanisms (two resolver fallbacks, TreeWalker's read-count path) had no C# counterpart. The only tests that failed on deleting them were our own, asserting the divergence.
3. **`$TMPDIR` differs between sandboxed and unsandboxed shells.** A file written there from one shell is not the file the other reads: step 02-05's first commit picked up a stale commit-message file left by an earlier step, and an early probe could not find its own inputs. Keep commit messages, baselines and other guard artifacts at an explicit, step-specific path.
4. **An adversarial reviewer without a compiler can be confidently wrong.** Review finding B1 (a claimed type error) was a false positive, disproved by a build. Check blocker claims about compilation by compiling.
5. **The macOS pre-commit gate does not cover Linux-only API differences.** `b5f7eeb` fixed a test that compiled on macOS and broke the Linux build. Only CI caught it.
6. **Equivalent-mutant arguments find design debt.** 02-03 M4 survived because choice-continuation parent frames are never resumed, which is now a follow-up.

---

## Deferred / Follow-Up

Filed:
- **#26** — newline de-duplication.
- **#27** — `setVariable`.
- **#28** — end-of-content errors (e.g. "unexpectedly reached end of content"; see S7).

From the feature-delta "Follow-ups — out of scope for #25":
- **Suspected tunnel-return-into-container bug** (unconfirmed): returning to `path.N` where child `N` is a container enters it with a single-frame stack. S6 preserves today's resolution; confirm with a fixture and file it.
- **Choice-continuation parent frames possibly unused** (02-03 M4): C# restores `threadAtGeneration` instead. Investigate and delete if there is no counterpart.
- **Symbol-level boundary rule** `r1_r5_no_engine_symbols`, and moving `ChoiceFlags` to `Decoder/` so the rule can cover it.
- **Divert-target values in `InkValue`** (C# `DivertTargetValue`). This changes the `variablesState` wire.
- **5B / 5C extractions**: a `ContainerStack` type, and `ContainerNode` navigation shared with the compiler. Fold `callFrameVariables` / `functionRootDepths` into `CallStackElement`.

Also noted:
- **Stale step-number comments in older Compiler files** that cite numbering from earlier features: `InkParser.swift:1007`, `RuntimeObjectEmitter.swift:108/126/486`, `WeaveEmitter.swift:159/786`, `StoryOutline.swift:95`.
- **Construct SSOT gaps**: the construct SSOT has no rows for multi-line sequences or `INCLUDE`, which the native compiler miscompiles silently.

---

## Source-of-Truth Pointers

- **Code**: `Sources/SwiftInkRuntime/Decoder/ContainerPath.swift`, `Engine/ContainerPathResolver.swift`, `Engine/CallStack.swift`
- **ADRs**: `docs/product/architecture/adr-016-typed-container-path.md`, `adr-017-typed-call-stack-and-pop-check.md`, `adr-018-save-format-compat-typed-paths.md`; ADR-004 partly superseded
- **Architecture**: `docs/product/architecture/brief.md` → `### typed-runtime-paths (Feature Addition)`
- **Tests**: `TypedPaths_LegacySaveCompatibilityTests`, `Engine_TypeCheckedPopTests`, `ContainerPathTests`, `ContainerPathResolverTests`, `CallStackElementTests`
- **Feature workspace** (preserved for the wave matrix): `docs/feature/typed-runtime-paths/`
