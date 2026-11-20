# Evolution — reference-fidelity-backlog

**Status**: COMPLETE. Seven open reference-fidelity issues (#28, #30, #33, #34, #35, #36, #37) traced to four root causes and fixed at the cause: 22 DELIVER steps on `main`, shipped in seven releases (2.1.2 to 2.1.6 patches, 2.2.0 minor, 2.2.1 patch), with no breaking API change. Step 06-01 (review follow-ups) is code- and test-only and unreleased.
**Date**: 2026-11-20 (DESIGN and DELIVER 2026-11-19 to 2026-11-20)
**Issues**: #28, #30, #33, #34, #35, #36, #37 (all closed). #27 was context only; it is decided and waits for 3.0.0.
**Predecessor**: `docs/evolution/2026-11-17-typed-runtime-paths.md`. Its typed paths and `ContainerPathResolver` are what the canonical visit-count keys build on, and it parked #28.

Waves: DESIGN → DELIVER → finalize. No DISCUSS wave (an issue backlog, not a user story) and no DISTILL wave, by maintainer decision: the issue repros, compiled by inklecate and used as oracle fixtures, plus the upstream conformance backlog, served as the acceptance tests. The durable lesson: **making a stop loud exposes everything a silent stop was hiding.** Turning on the end-of-content error (#28) found native layouts that had been diverging from inklecate unnoticed, and grew one planned step into four.

---

## Feature Summary

Before this feature, InkSwift disagreed with inklecate on inputs the oracle had never sampled:

- multi-line sequences replayed their first item and labelled-gather loops ran an extra pass (#33);
- `currentTags` kept the previous line's tags (#30);
- a story that ran out of content stopped silently, and `-> END` kept pending choices (#28);
- whole-number floats in inklecate JSON decoded as integers, so `1.0 / 3` was `0`; floats printed as `0.30000000000000004`; `1 == 1.0` was false and `"a" + 1` printed `1` (#37);
- a call to an undefined function compiled and played its last argument (#36);
- the native compiler dropped the space before a tag after an inline conditional (#34) and ignored backslash escapes (#35).

The DESIGN found **four root causes**, not seven edge cases:

| Cluster | Issues | Root cause |
|---|---|---|
| A — Continue boundary | #30, #28 | No per-`continue()` prologue or epilogue. Tags lived beside an untyped `[String]` output stream, so a tag had no position relative to the line break the lookahead read past. `done`, `end` and running out were indistinguishable. |
| B — Visit identity | #33 | Visit counts were keyed by the *spelling* of the path a container was entered by. inklecate gives a labelled gather an index (`0.0`) and a name (`0.loop`); sequential entry counted one, a divert the other. |
| C — Values and built-ins | #37, #36 | Numbers typed by `JSONDecoder` decode success, not token text; `String(Double)` printing; no C#-style operand coercion; FLOOR/CEILING returned int; built-in names defined in three places that disagreed; calls never resolved at compile time. |
| D — Content text | #35 (#34 isolated) | No shared escape-aware text scan: seven raw scanners in the compiler, and a both-sides trim before `#`. |

### Components Shipped

| Component | Path | Release | Decision |
|---|---|---|---|
| `InkJSONReader` (token-typed, pure Swift on bytes) | `Decoder/InkJSONReader.swift` | 2.1.2 | CREATE NEW, ADR-023 |
| `InkFloatText` (shortest `Float`, .NET "G" layout) | `Engine/StoryState.swift` | 2.1.2 | EXTEND, ADR-024 §2 |
| `VisitCounter` (sole owner of `visitCounts`, canonical keys, legacy merge, divert ancestor walk) | `Engine/VisitCounter.swift` | 2.1.3 | CREATE NEW, ADR-022 |
| Canonical path, `enclosures`, `lineage`, `contentAncestors` | `Engine/ContainerPathResolver.swift` | 2.1.3 / 2.1.5 | EXTEND |
| `OutputItem`, `OutputLine` (typed stream, pure line extraction) | `Engine/OutputStream.swift` | 2.1.4 | CREATE NEW, ADR-020 |
| Walker output helpers | `Engine/TreeWalker+Output.swift` | 2.1.4 | EXTRACT |
| `outputStreamTags` optional save key | `Engine/StoryState.swift` | 2.1.4 | EXTEND, ADR-020 §6 |
| Stop state, shared `forceEnd()` | `Engine/InkEngine.swift` | 2.1.5 | EXTEND, ADR-020 §4 |
| `FlowEndDiagnosis` (pure; C# end-of-content messages) | `Engine/FlowEndDiagnosis.swift` | 2.1.5 | CREATE NEW, ADR-020 §5 |
| Loose-end emission (`done` only where inklecate emits it) | `Compiler/Codegen/WeaveEmitter.swift`, `ConditionalEmitter.swift`, `LoweringContext` | 2.1.5 | EXTEND, ADR-021 |
| `InkValue.coerced`, `BinaryNativeFunction` | `Engine/StoryState.swift` | 2.1.6 | EXTEND, ADR-024 §3-4 |
| `NativeFunctionCatalog`, `NativeFunction` | `Decoder/NativeFunctionCatalog.swift` | 2.2.0 | CREATE NEW, ADR-025 |
| Compile-time call resolution (`throws` ripple) | `Compiler/Codegen/ExpressionLowering.swift` and callers | 2.2.0 | EXTEND, ADR-025 §4 |
| `ContentTextScanner` | `Compiler/Parser/ContentTextScanner.swift` | 2.2.1 | CREATE NEW, ADR-026 |
| SwiftLint R6 / R7 / R8 | `.swiftlint.yml` | 2.1.3 / 2.1.4 / 2.2.0 | `visitCounts[` only in `VisitCounter`; `outputStream.append(` only in `TreeWalker+Output`; `.nativeFunction("` only in `Decoder/` |

---

## Key Decisions

| ID | Decision | ADR |
|---|---|---|
| D1 | A1: typed output stream, pure line extraction, prologue/epilogue, transient stop reason, one `forceEnd()`; optional `outputStreamTags` key. A2 (snapshot/rewind loop) deferred to its own feature | [ADR-020](../product/architecture/adr-020-continue-boundary-typed-output-stream.md) |
| D2 | B1: one canonical path per container for visit counts; legacy keys merged on restore; **forward-only saves** | [ADR-022](../product/architecture/adr-022-canonical-container-identity-visit-counts.md) |
| D3 | Hand-written token-typed JSON reader; supersedes ADR-013's mechanism | [ADR-023](../product/architecture/adr-023-json-number-typing-by-token-text.md) |
| D4 | `Double` arithmetic, `Float` printing only (maintainer overrode 32-bit rounding); C# coercion; FLOOR/CEILING return float | [ADR-024](../product/architecture/adr-024-numeric-semantics-double-with-float-printing.md) |
| D5 | One native-function catalog shared by decoder, runtime and compiler; compile-time call resolution; `construct` strings renamed to the runtime's names; POW and `?`/`!?` added | [ADR-025](../product/architecture/adr-025-native-function-catalog.md) |
| D6 | #34 alone first; then one `ContentTextScanner` | [ADR-026](../product/architecture/adr-026-content-text-scanner.md) |
| D7 | Loose ends match inklecate: `done` only at the top level; no warning channel yet | [ADR-021](../product/architecture/adr-021-loose-end-emission.md) |

Plan changes made during DELIVER (feature-delta, DELIVER [WHY] table):

| # | Change |
|---|---|
| U1 | Float printing moved **before** the token-typed reader, so `2.0` never printed as `2.0` in between. |
| U2 | Visit identity split into refactor (01-04), canonical keys (01-05) and legacy restore (01-06); the split-key golden was captured before 01-05. |
| U3 | Flow-end state and `forceEnd()` (02-03) split from the epilogue (02-04). |
| U4 | 04-02, 04-03 and 04-04 shipped as **one minor** (2.2.0), superseding ADR-025's patch/minor split. |
| U5 | `srnd` pushed nothing (premise in ADR-025 was wrong); it now pushes void as C# does. A runtime behaviour change on the inklecate-JSON path. |
| U6 | `TURNS_SINCE(` / `READ_COUNT(` are refused at the call site, located, before their divert-target argument is parsed. |
| U7 | Construct-string renames accepted in 2.x (only diagnostic text changes). |
| U8 | A non-string operator on a string operand raises C#'s runtime error and ends the flow. |
| U9 | Undefined-function message uses inklecate's verbatim text. |
| U10 | Forward-only saves restated at 01-06. |
| U11 | New 01-07: count every container a divert enters (C# `VisitChangedContainersDueToDivert`). **Maintainer: a knot diverting to itself does not count a visit**, matching inklecate (inkle/ink#164, #297). |
| U12 | 02-03 also stopped the native compiler emitting `end` at a knot-level loose end; a ran-out stop does not set `isEnded`. |
| U13 | New 02-06: native emission reaches a safe exit where inklecate's does. Order became 02-03, 02-06, 02-05, 02-04. |
| U14 | New 02-07: a labelled root gather with its choices used up ends safely natively. |
| U15 | New 06-01: code and test follow-ups from the DELIVER review. |

---

## Work Completed

| Release | Step | Commit(s) | What |
|---|---|---|---|
| 2.1.2 | 01-01 | `85878bf`, `5af7220`, `8c27771` | #34. First a trailing-only trim; its "no trim" mutant survived as equivalent, and inklecate emits the literal untrimmed, so the follow-up removed the trim. `8c27771` fixed the T3 expectation that `5af7220` left red. |
| 2.1.2 | 01-02 | `a8f81f7` | Floats print as inklecate prints them (.NET "G" layout: `2`, `0.33333334`, `1E+20`). Storage stays `Double`. |
| 2.1.2 | 01-03 | `9bea37a` | `InkJSONReader`: a number is a float iff its token has `.`, `e` or `E`. Probe gains `2.0` and `1e2`. `TestArithmetic` (runtime) re-enabled. |
| 2.1.3 | 01-04 | `e5b423b` | `VisitCounter` refactor; R6; `visit` moved into the engine. Behaviour-neutral. |
| 2.1.3 | 01-05 | `e138d0e` | #33: canonical keys (C# `Object.path`). Split-key golden save captured first. |
| 2.1.3 | 01-06 | `636cdfb` | Legacy keys converted and summed on restore. Fixes #33. |
| 2.1.3 | 01-07 | `1333bd4` | Divert ancestor counting, count-start-only honoured; self-divert keeps its count. `TestKnotStitchGatherCounts` (runtime) re-enabled. |
| 2.1.4 | 02-01 | `56d08ed` | Typed output stream, pure `OutputLine`, R7. Behaviour-neutral, wire unchanged. |
| 2.1.4 | 02-02 | `1cb2fac` | #30: tags positioned in the stream; prologue clears them; `outputStreamTags`; choices offered only after the last buffered line. |
| 2.1.5 | 02-03 | `7115902` | `forceEnd()` shared by `end` and `refusePop`; `-> END` discards pending choices; native knot-level `end` removed (U12). |
| 2.1.5 | 02-06 | `09048c7` | Native safe exits: `-> DONE`/`-> END` lowered everywhere; root rejoins and final gathers reach `done`. 18 conformance stories pinned. |
| 2.1.5 | 02-05 | `77c2f49`, `c81646c` | Only the root weave ends in `done`; `terminateArm` reworked; TheIntercept's "sipping" line pinned first. |
| 2.1.5 | 02-04 | `e4e013d` | #28: `FlowEndDiagnosis` and the C# messages. Two runtime ran-out stops fixed first (divert frame rebuild, unterminated last line). |
| 2.1.5 | 02-07 | `d994281` | Auto-entered root gather gets the root's `done`. |
| 2.1.6 | 03-01 | `a55b4a4` | #37: one coercion point (`1 == 1.0`, `"a" + 1` = `a1`), FLOOR/CEILING float, string-operand runtime error. |
| 2.2.0 | 04-01 | `5997b0b` | `NativeFunctionCatalog`, typed `NodeKind.nativeFunction`, exhaustive switch, R8. Behaviour-neutral. |
| 2.2.0 | 04-02 | `38e8920`, `017c1eb` | `throws` ripple; compile-time call resolution, arity errors, `.unresolvedReference`. |
| 2.2.0 | 04-03 | `52fbdd2` | Unsupported built-ins rejected under the runtime's names; SEED_RANDOM plays; `srnd` pushes void. Fixes #36. |
| 2.2.0 | 04-04 | `bce20d4` | POW, `?`/`!?`, `has`/`hasnt` on both paths. |
| 2.2.1 | 05-01 | `cc9b65e` | `ContentTextScanner` behind every content-text consumer, escape-agnostic. Behaviour-neutral. |
| 2.2.1 | 05-02 | `8c55937` | #35: escape-aware; glue before a tag. |
| — | 06-01 | `8cde625`, `0cc5b56` | Review follow-ups (U15): escape-agnostic mode removed, catalog `takesDivertTarget`, `FallThrough.runOut`, stronger tests. No release. |

Plan-only commits: `eae8365` (roadmap), `8629978` (pre-commit before `des-commit`), `4a0d91e`, `a1dcf8c`, `c19f06d`, `ff5929f`, `4a19e34`, `6745047`.

Process notes (review finding #14): 01-01 has two RED/GREEN/COMMIT cycles in `execution-log.json` (the trim removal `5af7220` and the test fix `8c27771` follow `85878bf`). 01-02's COMMIT was first logged SKIPPED, blocked by the red trunk `5af7220` left, then committed as `a8f81f7` once `8c27771` landed. `des-verify-integrity` passes for all 22 steps.

Conformance: 18 test modes across 13 upstream tests left the backlog (`TestArithmetic`, `TestGatherReadCountWithInitialSequence`, `TestVisitCountBugDueToNestedContainers`, `TestVisitCountsWhenChoosing`, `TestKnotStitchGatherCounts`, `TestTagsInSeq`, `TestConditionalChoiceInWeave2`, `TestDoneStopsThread`, `TestChoiceDivertsToDone`, `TestFloorCeilingAndCasts`, `TestStringTypeCoersion`, `TestStringContains`, `TestEscapeCharacter`). Each behaviour-neutral step (01-04, 02-01, 04-01, 05-01, 06-01) diffed the backlog failure list before and after: empty every time.

---

## Lessons Learned

1. **`des-commit` bypasses the pre-commit gate.** It commits with `--no-verify`, so `5af7220` landed a red test on the trunk (fixed by `8c27771`), and the next step's commit was blocked. CLAUDE.md now requires running `.githooks/pre-commit` before every `des-commit`.
2. **Skipping DISTILL worked for an issue backlog.** Each issue's repro, compiled by inklecate and continued past the construct, became the step's acceptance test; the conformance backlog was the rest. Hand-written expectations were still needed where no oracle exists or the oracle cannot see the difference:
   - save-wire behaviour (`outputStreamTags`, legacy key merge, forward-only goldens);
   - compiler rejections (located errors, `construct` names, the catalog consistency test);
   - the blueprint-level `" after. "` text run, invisible in played output;
   - the `~ return` end-of-content message, which no fixture reaches;
   - the deliberate 64-bit precision divergence and float spelling edge cases (values taken from `inklecate -p` probes).
3. **A silent stop hides divergence.** Enabling the end-of-content error (02-04) turned 14 enabled native conformance tests red: their native emission ran out where inklecate's JSON ends safely. That produced 02-06 and 02-07 and parked 02-04 in a stash until they landed. Making failures loud is also a discovery tool.
4. **Our own tests sometimes asserted InkSwift-only behaviour.** Three had to be corrected to the oracle: the `slice03` self-divert read count (01-07), the T3 trim expectation (01-01), and the string escape test (`"He said \"hello\""`, 05-02). As in the predecessor feature, a failing test is not automatically a regression; check it against inklecate.
5. **A surviving "no-op" mutant can mean the mechanism should not exist.** 01-01's trailing-only trim survived the "no trim" mutant; inklecate has no such trim, so it was deleted rather than defended (CLAUDE.md "The oracle is necessary, not sufficient").
6. **`$TMPDIR` differs between sandboxed and unsandboxed shells** (again). One `des-commit` picked up a stale message file and was amended. Keep commit messages at an explicit, step-specific path.
7. **Probe before predicting.** Several design premises were wrong and only probes showed it: `srnd` pushed nothing (U5), the undefined-function message (U9), ancestor counting being observable (U11), the exponent spelling (.NET `1E+20`).

---

## Issues Encountered

- **Red trunk** at `5af7220` (see lesson 1); one commit blocked, then recovered.
- **Scope growth in #28**: three new steps (02-06, 02-07, and the 02-03 compiler change) to keep native and inklecate paths agreeing before the error was released. ADR-021 §3's "same release" rule held: all of it shipped in 2.1.5.
- **ADR-020 §4 deviation**: a ran-out stop does not set `isEnded`, or every ordinary choice-point save would carry `isEnded = true` (U12). The ADR text is updated.
- **Behaviour changes users may notice**: forward-only saves (2.1.3), self-diverting knots keep their read count (2.1.3), `-> END` discards choices (2.1.5), `srnd` pushes void on the JSON path (2.2.0), `CompileError.construct` strings renamed (2.2.0). All were called out in release notes.

---

## Follow-Up

Filed during the work:

- **#38** compile-time warnings (warning channel, ADR-021 §2).
- **#39** runtime and save-format warnings.
- **#40** logic in choice text (`{…}` kept literally by the native compiler).
- **#41** division by zero, and unary operators on strings.
- **#42** native labelled-root-gather loop loses a choice.
- **#43** glue before a tag vs inkle/ink#923: `inklecate -p` also joins the following line. **Maintainer decision pending.**
- **#44** the `"void"` string sentinel.
- **#45** `try?` in `WeaveEmitter`.

**#46:** reading a temp whose declaration was skipped (`{flag: ~ temp y = 1}` then `y`) pushes nothing in `handleVariableReference`; C# warns ("Variable not found: 'y'. Using default value of 0") and pushes 0. Found in 06-01 (review #7); the stack-underflow guards stay until it is fixed.

Deferred by design:

- **A2**, the snapshot/rewind `ContinueInternal` loop (ADR-020): its own feature, spike first, only if the glue backlog proves loop-shaped.
- **C3 / `Float` storage** and **#27** typed `setVariable`: 3.0.0.

---

## Quality State at Finalize

- **Suite**: green through the pre-commit gate (SwiftLint `--strict` + `swift test`); 818 tests at `8c27771`, 955 at `05-01`.
- **Mutation testing**: automated disabled project-wide; each step ran 3-6 manual mutations, reported in its commit message. Survivors were killed with a test (02-01 M4) or argued equivalent (01-01 "no trim", 01-05 guard removed instead, 02-05 M6).
- **CodeScene**: new files at 10.0 (`InkJSONReader`, `VisitCounter`, `OutputStream`, `TreeWalker+Output`, `FlowEndDiagnosis`, `NativeFunctionCatalog`), except `ContentTextScanner` at 9.68 (Primitive Obsession). `InkDecoder` 8.08 → 8.73, `TreeWalker` 7.17 → 7.83, `ConditionalEmitter` 9.68 → 10.0; no file dropped below its baseline.
- **Invariants**: no DISTILL-authored `.disabled` ATs exist; conformance `.disabled` entries are backlog, not unfinished delivery.

---

## Artifact Migration

None needed (SSOT model). ADR-020 to ADR-026 were written directly to `docs/product/architecture/`, and `brief.md` → `### reference-fidelity-backlog (Feature Addition)` is the architecture record, now marked IMPLEMENTED with releases. The workspace has no `discuss/`, `design/` or `distill/` subfolders. `docs/feature/reference-fidelity-backlog/` stays as delivery history: `feature-delta.md`, `deliver/roadmap.json`, `deliver/execution-log.json`.

---

## Source-of-Truth Pointers

- **ADRs**: `docs/product/architecture/adr-020-continue-boundary-typed-output-stream.md`, `adr-021-loose-end-emission.md`, `adr-022-canonical-container-identity-visit-counts.md`, `adr-023-json-number-typing-by-token-text.md`, `adr-024-numeric-semantics-double-with-float-printing.md`, `adr-025-native-function-catalog.md`, `adr-026-content-text-scanner.md`. Amended: ADR-009, ADR-013 (mechanism superseded), ADR-016, ADR-017, ADR-018.
- **Architecture**: `docs/product/architecture/brief.md` → `### reference-fidelity-backlog (Feature Addition)`
- **Differences**: `docs/reference/differences-from-inklecate.md`, `docs/product/ink-feature-reference.md`
- **Feature workspace** (preserved for the wave matrix): `docs/feature/reference-fidelity-backlog/`
