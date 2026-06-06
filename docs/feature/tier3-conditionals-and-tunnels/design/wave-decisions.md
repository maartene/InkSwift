# DESIGN Decisions — tier3-conditionals-and-tunnels

**Wave**: DESIGN
**Architect**: Morgan (nw-solution-architect)
**Date**: 2026-06-05
**Branch**: native-runtime
**Mode**: Propose

---

## Key Decisions

### D1 — Inline Conditional Text (C1): Existing `isConditional` divert pathway is sufficient

The `classifyDict` method already decodes `{"->": path, "c": true}` as `.divert(isConditional: true)`. `InkEngine.handleDivertNode` already calls `applyConditionalBranch` for conditional diverts, which rewrites `containerStack` to the target branch. The inline `{c: a|b}` form is structurally handled by this path.

**Implication for crafter**: C1 begins with fixture compilation and inspection. Write the test first (RED). The existing machinery either passes or reveals a specific gap in `applyConditionalBranch`. Do not add code before seeing the test fail for the right reason.

**Rejected alternatives**:
- New `.inlineConditional` NodeKind case (over-engineering; decoder should not interpret branch structure)
- Engine-level container pattern detection (couples engine to encoding details)

### D2 — Block and Switch Conditionals (C2): Same handler as C1

Block conditionals and switch-style dispatch use the same `isConditional` divert encoding in inklecate. Switch dispatch uses repeated `ev…==…/ev` blocks with a conditional divert per case. The existing native function `==` handler and conditional divert handler are sufficient.

**Implication for crafter**: C2 begins only after C1 is green. Inspect the compiled block/switch fixture before writing handlers. If switch dispatch uses an equality pattern not yet in `handleNativeFunction`, add the missing case. Do not add a dedicated switch-dispatch method unless fixture inspection proves the existing path insufficient.

**Rejected alternatives**:
- Separate `applySwitchBranch` method (premature; adds code before evidence of need)
- `.switchConditional` NodeKind case (decoder becomes pattern-aware)

### D3 — Ink Functions (C3): Reuse `returnStack`; `f()` key added to classifyDict; `~ret` intercepted in InkEngine

The `{"f()": path}` dict key is not currently handled — add it to `classifyDict` as `.divert(target: path, isConditional: false, isVariable: false)`. The `~ret` control command is already classified (it is in `controlCommands`) but has no handler — `InkEngine.stepToNextLine` must intercept `.controlCommand("~ret")` before calling `walker.dispatchNode`, pop from `returnStack`, and call `applyDivert(target: popped)`.

No new StoryState field. The `voidValue` no-op in TreeWalker is already correct for void-function suppression.

**Implication for crafter**: Two precise changes: (1) one new `if let path = dict["f()"]` clause in `classifyDict`; (2) one new pre-dispatch intercept in `stepToNextLine` for `~ret`. Verify `returnStack` is balanced before and after each function call in tests.

**Rejected alternatives**:
- Separate `functionCallStack: [String]` (conceptually wrong at Ink VM level; adds format complexity)
- Typed `CallFrame` enum replacing `returnStack` (breaking StoryState format change; not justified by scope)

### D4 — Tunnels (T1/T2): New `.tunnelDivert` NodeKind; InkEngine intercepts `->->` and `~ret`

`{"->t->": path}` requires a new NodeKind case: `.tunnelDivert(target: String)`. `InkEngine.stepToNextLine` intercepts `.tunnelDivert` (push return address to `returnStack`, call `applyDivert`) and `.controlCommand("->->")` (pop `returnStack`, call `applyDivert`). The return address is the current container's path with its post-tunnel execution index.

`->->` is already in `controlCommands` and classifies to `.controlCommand("->->")`. No decoder change needed for it. T2 (nested tunnels) requires no additional changes — `returnStack` is already `[String]` (array) by ADR-004 design.

**Implication for crafter**: One new NodeKind case. Two pre-dispatch intercepts in `stepToNextLine`. Inspect the compiled tunnel fixture to confirm the `->t->` key format and the shape of the return address before implementing.

**Rejected alternatives**:
- New `isTunnel: Bool` flag on `.divert` (three flags on one case; combinatorial coupling)
- Synthesising pairs of nodes in the decoder (decoder becomes a structural transformer)

### D5 — Reference Parameters (T3): New `.variablePointer` NodeKind; new `callFrameVariables` StoryState field

`{"^var": name, "ci": N}` requires a new NodeKind case: `.variablePointer(name: String, contextIndex: Int)`. A new StoryState field `callFrameVariables: [[String: InkValue]]` (decoded with `decodeIfPresent`, default `[]`) provides per-frame local scope. `InkEngine` pushes a new frame dictionary on function call and pops it on `~ret`.

**Deferral gate**: If fixture inspection during RED reveals The Intercept's ref-param functions use only global variables (`ci == 0` always), T3 can be implemented without `callFrameVariables` by treating `.variablePointer` with `ci == 0` as `.variableReference`. The crafter decides during RED. The architecture supports both paths.

**Rejected alternatives**:
- Reuse `.variableReference` ignoring `ci` (incorrect for `ci > 0`; creates known-broken behaviour)
- Frame naming convention in flat `variablesState` (fragile; not how the Ink VM works)

---

## Architecture Summary

Tier 3 extends four existing files with no new source files. The dependency direction (Facade → Engine → Decoder) is unchanged. All changes are additive.

### Components Touched

| Component | File | Nature of change |
|---|---|---|
| `NodeKind` | `Decoder/NodeKind.swift` | +2 new cases: `.tunnelDivert(String)`, `.variablePointer(name:, contextIndex:)` |
| `InkDecoder` | `Decoder/InkDecoder.swift` | +3 new `classifyDict` clauses: `"f()"`, `"->t->"`, `"^var"` |
| `InkEngine` | `Engine/InkEngine.swift` | +3 pre-dispatch intercepts in `stepToNextLine`: `.tunnelDivert`, `->->`, `~ret`; function frame push/pop for T3 |
| `StoryState` | `Engine/StoryState.swift` | +1 new field (T3 only): `callFrameVariables: [[String: InkValue]]` with `decodeIfPresent` |
| `TreeWalker` | `Engine/TreeWalker.swift` | Minimal or no changes; engine-intercepted nodes bypass `dispatchNode` |

### What is NOT changing

- `Story.swift` (Facade) — no public API changes
- `ContainerNode.swift` — no structural changes
- `TagParser.swift` — untouched
- The C4 Level 3 component structure — no new components
- `InkSwift` module — frozen, no changes

---

## Reuse Analysis

| Existing Component | File | Overlap | Decision | Justification |
|---|---|---|---|---|
| `InkDecoder.classifyDict` | `Decoder/InkDecoder.swift` | Entry point for all new node types | Extend | Three additive `if let` clauses before the unknown fallback; no restructuring of existing clauses |
| `NodeKind` | `Decoder/NodeKind.swift` | Enum exhaustiveness enforced by compiler | Extend | Two new internal cases; every existing `switch` on `NodeKind` gains two new arms (compiler-enforced) |
| `InkEngine.stepToNextLine` | `Engine/InkEngine.swift` | Pre-dispatch intercept loop | Extend | Three new `if case` checks following the established `.divert`/`.choicePoint` pattern |
| `InkEngine.applyDivert` | `Engine/InkEngine.swift` | Tunnel and function return diverts use this existing method | Extend (reuse) | Return address popped from `returnStack` is passed directly to `applyDivert`; no new divert method |
| `InkEngine.applyConditionalBranch` | `Engine/InkEngine.swift` | C1/C2 conditional branch resolution | Extend (if needed) | Existing method is the target of all conditional diverts; extension only if fixture reveals multi-branch gap |
| `StoryState.returnStack` | `Engine/StoryState.swift` | Reused for both function frames (C3) and tunnel frames (T1/T2) | Reuse | Already `[String]`; `decodeIfPresent` already in place from ADR-004 |
| `TreeWalker.dispatch` | `Engine/TreeWalker.swift` | `.voidValue` no-op already correct; `.variablePointer` if engine-dispatched here | Extend (minimal) | At most one new `case` for `.variablePointer`; engine may handle it entirely |
| `InkDecoder.controlCommands` set | `Decoder/InkDecoder.swift` | `->->` and `~ret` already in set | Reuse (no change) | Already classified correctly; only the InkEngine handler is missing |

---

## Technology Stack

No changes. Tier 3 uses only Foundation (JSONSerialization for decoder, Codable for state). Swift 5.8+, XCTest, SwiftLint. No new runtime dependencies.

| Component | Choice | License | Change? |
|---|---|---|---|
| Swift | 5.8+ (SPM) | Apache 2.0 | No |
| Foundation | Bundled | Apple APSL | No |
| XCTest | Bundled | Apple | No |
| SwiftLint | 0.55+ | MIT | No |

---

## Constraints Established

All constraints are inherited from DISCUSS decisions and the project brief. No new constraints are introduced by the DESIGN wave.

1. **No new runtime dependencies** — Foundation only; no third-party packages.
2. **All new StoryState fields use `decodeIfPresent` with safe defaults** — `callFrameVariables` decoded with `decodeIfPresent`, default `[]`.
3. **NodeKind stays internal (Rule R2)** — new cases `.tunnelDivert` and `.variablePointer` carry no `public` modifier.
4. **JSONSerialization only in `Decoder/` (Rule R3)** — new `classifyDict` clauses remain inside `InkDecoder.swift`.
5. **Dependency direction: Facade → Engine → Decoder (Rule R1)** — unchanged; `InkDecoder` imports nothing from `Engine/`.
6. **Test fixtures must use inklecate-compiled JSON** — no hand-crafted JSON for any Tier 3 test. Inklecate at `/Users/maartene/Downloads/inklecate_mac/inklecate`.
7. **`->->` and `~ret` are pre-classified** — crafter wires the existing classified nodes; does not re-classify them.
8. **macOS-arm64 only** — Linux CI deferred.
9. **Swift Testing style** — backtick function-name style mandatory; string-label form forbidden.
10. **Save/restore invariant** — every new behaviour must survive `saveState() → restoreState()` round-trip.

---

## Upstream Changes

None. Tier 3 derives directly from Feature Coverage Matrix rows 22–24, 29–30, 34–35. No DISCOVER or DISCUSS assumptions have changed. ADR-004 (call/return mechanism) anticipated tunnels and functions explicitly — the design validates, rather than revises, its decisions.

---

## ADRs

No new ADRs are raised for Tier 3. The five decisions above are architecturally significant but not independently durable enough to warrant standalone ADRs:

- D1/D2 (conditionals) are implementation validations of the existing `isConditional` divert pathway.
- D3/D4 (functions, tunnels) are direct extensions of ADR-004 — the ADR explicitly anticipated both features.
- D5 (reference parameters) introduces the only new StoryState field; it is documented in the Tier 3 subsection of `brief.md` with the `decodeIfPresent` annotation.

If the crafter discovers during RED that the inklecate encoding deviates materially from the assumed structure for any decision, an ADR amendment should be raised at that point.
