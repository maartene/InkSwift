# DISTILL Upstream Issues — tier2-choice-mechanics

These issues were found during acceptance-test creation (DISTILL wave) by cross-referencing the DESIGN wave decisions against the actual inklecate-compiled JSON fixtures and the authoritative Ink JSON runtime format specification (`docs/ink_JSON_runtime_format.md`).

---

## Issue 1 — DESIGN D1/D2: Flag Bit Table Is Wrong

**Source**: `docs/product/architecture/brief.md` → `### Tier 2 — Choice Mechanics`, Flag Bit Reference table  
**Gap**: The brief's flag bit table assigns the wrong bit numbers to once-only and sticky choices.

The brief states:
> A `*` (once-only) choice has bit 1 unset (`flags & 2 == 0`).  
> A `+` (sticky) choice has bit 1 set (`flags & 2 != 0`).

The authoritative Ink JSON spec (`docs/ink_JSON_runtime_format.md`) and inklecate output contradict this:

| Bit | Value | Ink spec name | Brief name (WRONG) | Actual inklecate evidence |
|-----|-------|---------------|--------------------|--------------------------|
| 0 | 1 | Has condition | isConditional | `flg: 21` for `* {cond} [text]` ✓ |
| 1 | 2 | Has start content | isSticky | `flg: 20` for `* [text]` — bit 1 is NOT set ✗ |
| 2 | 4 | Has choice-only content | isInvisibleDefault | `flg: 20` for `* [text]` — bit 2 IS set ✗ |
| 3 | 8 | Is invisible default | isGatherFallback | `+ []` compiles to `flg: 0`, not `flg: 8` — see Issue 2 |
| 4 | 16 | Once only | (not mentioned) | `* [text]` → `flg: 20` = `0x10 + 0x04` ✓ |

**Correct detection rules for DELIVER**:
- Once-only choice: `flags & 0x10 != 0` (bit 4, value 16)
- Sticky choice: `flags & 0x10 == 0` (bit 4 not set)
- Conditional choice: `flags & 0x01 != 0` (bit 0, value 1) ← this is already correct in DESIGN D2

**Impact on DESIGN D1**: The implementation must check `flags & 16 != 0` (OnceOnly bit), not `flags & 2 == 0` (which is always true for bracketed choices). Any implementation following the brief literally will suppress ALL bracketed choices rather than only once-only ones.

**Action**: The DELIVER crafter must use `flags & 0x10` (value 16) for once-only detection, not `flags & 0x02` as the brief's table implies.

---

## Issue 2 — DESIGN D4: Invisible Default Flag Detection Is Wrong

**Source**: `docs/product/architecture/brief.md` → `#### D4 — Invisible defaults (S4)`  
**Gap**: D4 states "the engine also skips choices where `flags & 4 != 0` (invisible defaults)". But `flags & 4` is the `HasChoiceOnlyContent` bit — it is set for ALL bracketed choices like `* [text]`, not for invisible defaults.

Actual inklecate output for `+ []` (invisible default): **`flg: 0`** — NOT `flg: 8` and NOT `flg: 4`.

The Ink JSON spec says bit 3 (value 8) is `IsInvisibleDefault`. But inklecate v0.9 compiles `+ []` to `flg: 0`. The detection logic therefore cannot rely on a single flag bit.

**Observed inklecate warning during fixture compilation**:
> `WARNING: 'slice04-invisible-defaults.ink' line 3: Blank choice - if you intended a default fallback choice, use the * -> syntax`

This suggests `+ []` may be deprecated syntax in inklecate v0.9+. The compiled JSON still produces `flg: 0` and the continuation text is preserved in the named container.

**Proposed detection logic for DELIVER**:
An invisible default choice is one that satisfies ALL of the following:
1. Not once-only: `flags & 0x10 == 0`
2. No text to show (neither start content nor choice-only content): `flags & (0x02 | 0x04) == 0`
3. No condition: `flags & 0x01 == 0`

Alternatively, if `+ []` should be replaced with `* -> label` syntax per inklecate's suggestion, the crafter should update the Ink source fixture and recompile before implementing D4.

**Impact**: If D4 is implemented as written (`flags & 4 != 0`), it will incorrectly suppress ALL bracketed choices rather than only invisible defaults. The acceptance tests in Slice04 will catch this.

---

## Issue 3 — DESIGN D3: CNT? Is a Node Type, Not a READ_COUNT Native Function

**Source**: `docs/product/architecture/brief.md` → `#### D3 — READ_COUNT / visit counts (S3)`  
**Gap**: D3 states "`TreeWalker.handleNativeFunction` gains a `case "READ_COUNT"` branch. It pops the top of `evalStack` as a string (a dotted-path key string)."

However, in actual inklecate-compiled JSON, visit count lookup is expressed as a DICT node `{"CNT?": "knot_name"}`, NOT as a `"READ_COUNT"` native function string. The key is embedded inline in the node, not on the evalStack.

Evidence from `slice03-read-counts.ink.json`:
```json
{"CNT?": "café"}
```

The Ink JSON spec confirms (`docs/ink_JSON_runtime_format.md` § Read count):
> `{"CNT?": "the_hall.light_switch"}` — gets the read count of the container at the given path.

The current `InkDecoder` classifies `{"CNT?": "key"}` dicts via the unknown-fallback path:
```swift
return .controlCommand(dict.keys.first ?? "?")
// → .controlCommand("CNT?") — silently ignored by TreeWalker
```

There is no `NodeKind.readCount(String)` case; the decoder and walker both need changes.

Additionally, the `"visit"` control command in `TreeWalker.handleControlCommand` (which increments visit counts using `state.pointer.containerPath`) is likely NOT triggered by inklecate-compiled stories. Actual visit counting in Ink JSON is driven by container `#f` flags (bit 0x1 = "Visits"), not by inline `"visit"` command strings.

**Required DELIVER changes for Slice 03**:
1. `NodeKind` gains a new case: `.readCount(String)` (the path key)
2. `InkDecoder.classifyDict` handles `{"CNT?": key}` → `.readCount(key)`
3. `TreeWalker.dispatch` handles `.readCount(key)` by looking up `state.visitCounts[key] ?? 0` and pushing `.int(count)` to `evalStack`
4. `InkEngine` (or `TreeWalker`) must increment `visitCounts[knotPath]` when entering a container whose `#f` flag has bit 0x1 set — this is when the knot/stitch is entered, before any content is evaluated.

**Impact**: Without these changes, `{café > 1: ...}` evaluates `café` as 0 always, the `>` comparison pushes `false`, and the conditional text never shows. All Slice 03 acceptance tests will be RED.

---

## Summary

| Issue | Affects | Severity |
|-------|---------|----------|
| Wrong once-only bit (0x02 vs 0x10) | D1, all Slice 01 tests | HIGH — wrong bit suppresses all bracketed choices |
| Wrong invisible default detection (0x04 vs correct logic) | D4, all Slice 04 tests | HIGH — wrong bit suppresses all bracketed choices |
| CNT? is a node, not READ_COUNT native function | D3, all Slice 03 tests | HIGH — visit counts never update, conditional text never shows |
