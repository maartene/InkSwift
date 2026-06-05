# DESIGN Decisions — tier2-choice-mechanics

## Key Decisions

- [D1] **Once-only suppression**: The choice-collection loop in `InkEngine.stepToNextLine` skips any choice where `flags & 0x10 != 0` (once-only bit 4 is SET) AND `state.chosenChoiceTargets` already contains its target path. `InkEngine.chooseChoice(at:)` records the target in `chosenChoiceTargets` for every once-only choice that is executed.
- [D2] **Conditional gating**: When `flags & 1` is set, the engine pops the boolean result left on `state.evalStack` by the preceding `ev … /ev` block; if the value is `false`, the choice is skipped. The pop is always performed to keep the stack balanced.
- [D3] **CNT? dict node / visit counts**: Visit count lookup in inklecate-compiled JSON is a dict node `{"CNT?": "knot_name"}`, NOT a native function string. Required changes: (1) `NodeKind` gains `.readCount(String)`; (2) `InkDecoder.classifyDict` handles `{"CNT?": key}` → `.readCount(key)`; (3) `TreeWalker.dispatch` handles `.readCount(key)` by pushing `state.visitCounts[key] ?? 0` as `.int`; (4) `InkEngine`/`TreeWalker` increments `visitCounts[path]` when entering a container whose `#f` flag has bit `0x1` (CountVisits) set.
- [D4] **Invisible defaults**: inklecate v0.9 compiles `+ []` to `flg: 0`, so `flags & 4` or `flags & 8` do NOT reliably detect invisible defaults. Detection uses all three conditions: `flags & 0x10 == 0` (not once-only) AND `flags & 0x06 == 0` (no text content) AND `flags & 0x01 == 0` (no condition). The collection loop skips choices matching this criteria and records the first such target in a local `pendingInvisibleDefault`. After collection, if no visible choices remain and `pendingInvisibleDefault` is non-nil, the engine applies that divert and continues the step loop — auto-divert per the Ink specification.
- [D5] **StoryState — `chosenChoiceTargets`**: New `Set<String>` field on `StoryState`, `Codable`, decoded with `decodeIfPresent` defaulting to `[]`. `CodingKeys` extended accordingly. Backward-compatible with any existing saved state.
- [D6] **ChoiceData — `flags`**: `ChoiceData` gains `flags: Int`, `Codable`, `decodeIfPresent` defaulting to `0`. Used by `chooseChoice(at:)` to decide whether to record the target in `chosenChoiceTargets`, and populated during choice collection from the in-flight choice node.

## Architecture Summary

- **Pattern**: Modular monolith with ports-and-adapters (dependency inversion at layer boundaries). All Tier 2 changes are contained within the Engine layer.
- **Paradigm**: Object-Oriented with value-type state (`StoryState` is a `struct`). No new types introduced.
- **Key components modified**:
  - `InkEngine` (Engine layer) — choice-collection loop extended with D1, D2, D4 gating; `chooseChoice(at:)` extended with D1 recording
  - `StoryState` (Engine layer) — `chosenChoiceTargets` field added (D5); `ChoiceData.flags` field added (D6)
  - `TreeWalker` (Engine layer) — `.readCount(key)` dispatch case added; `#f` flag visit count increment added (D3)
  - `NodeKind` (Decoder layer) — `.readCount(String)` case added (D3)
  - `InkDecoder` (Decoder layer) — `classifyDict` handles `{"CNT?": key}` (D3)

## Reuse Analysis

| Existing Component | File | Overlap | Decision | Justification |
|---|---|---|---|---|
| `InkEngine` | `Engine/InkEngine.swift` | Choice-collection loop; `chooseChoice(at:)` | Extend | Collection loop and dispatch already exist; once-only, conditional, and invisible-default logic is additive gating within those loops |
| `StoryState` | `Engine/StoryState.swift` | Codable state struct; `ChoiceData` nested type | Extend | One new field on `StoryState` and one new field on `ChoiceData`; both use `decodeIfPresent` for backward compatibility |
| `TreeWalker` | `Engine/TreeWalker.swift` | `dispatch` switch | Extend | `.readCount(key)` is one new `case`; `#f` bit `0x1` check increments `visitCounts` on container entry |
| `NodeKind` | `Decoder/NodeKind.swift` | Node kind enum | Extend | New case `.readCount(String)` for `{"CNT?": key}` dict nodes |
| `InkDecoder` | `Decoder/InkDecoder.swift` | `classifyDict` | Extend | Match `{"CNT?": key}` → `.readCount(key)` before the unknown-fallback path |

No new source files are introduced.

## Technology Stack

No changes to the technology stack. All decisions are implemented in existing Swift source files using Foundation (`Codable`, `Set`) — already in the stack.

| Component | Choice | License | Rationale |
|---|---|---|---|
| Swift 5.8+ | Existing | Apache 2.0 | Required by project |
| Foundation (`Codable`, `Set`) | Existing | Apple APSL | `decodeIfPresent` enables backward-compatible state evolution |
| SwiftLint | Existing | MIT | Architectural boundary enforcement unchanged; no new rules required for Tier 2 |

## Constraints Established

- **No new source files**: All changes live in `InkEngine.swift`, `StoryState.swift`, `TreeWalker.swift`, `NodeKind.swift`, and `InkDecoder.swift`. The folder layout documented in `brief.md` is unchanged.
- **Backward-compatible state serialization**: Both `chosenChoiceTargets` and `ChoiceData.flags` use `decodeIfPresent` with safe defaults. Existing `StoryState` JSON round-trips without error.
- **Key-scheme validation via real fixtures**: `CNT?` key-scheme correctness is verified by Slice 03 inklecate-compiled fixtures, not pre-emptive guessing (see feedback in `memory/feedback_real_compiler_json.md`).
- **Flag bit semantics are additive**: The pre-Tier-2 `flags & 8` path is not changed. D1 uses bit 4 (`0x10`); D2 uses bit 0 (`0x01`); D4 uses the combination `flags & 0x17 == 0` to detect invisible defaults (since inklecate v0.9 compiles `+ []` to `flg: 0`, not `flg: 8`).

## Upstream Changes

- `docs/product/architecture/brief.md` — `### Tier 2 — Choice Mechanics` subsection added under `## Application Architecture`, recording D1–D6, the flag bit reference table, and the reuse analysis.
- No ADR additions required: Tier 2 decisions are evolutionary extensions within the architectural style already established (ports-and-adapters, Engine layer ownership of execution state) and documented in ADR-001 through ADR-004.
