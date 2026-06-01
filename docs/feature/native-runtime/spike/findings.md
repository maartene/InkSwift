# SPIKE Findings — native-runtime / Ink JSON Parser

## Assumption Tested
Can we model the Ink JSON runtime format as Swift types and successfully decode a real `.ink.json` file into those types?

## Verdict: ✅ WORKS

## Probe Details
- Probe code: `/tmp/spike_ink_json_parser/Sources/main.swift`
- Test fixture: `Tests/InkSwiftTests/test.ink.json` (inkVersion 21)
- Approach: `JSONSerialization` + custom recursive walker

## Results
- **146 content nodes** visited across the entire story tree
- **Zero unknown nodes** — every node type in the real fixture was classifiable
- Node kinds covered:
  - Control commands: `ev`, `/ev`, `str`, `/str`, `pop`, `done`, `end`
  - Text and newlines
  - Diverts (static, variable-target, conditional)
  - Choice points (with flags)
  - Variable assignment (`VAR=` global, `temp=` local)
  - Variable reference (`VAR?`)
  - Divert target values (`^->`)
  - Tag open/close markers (`#`, `/#`)
  - Int and float values
  - Native functions (`srnd`, and the full operator set)
  - Containers (anonymous and named, with flag bits)
- `listDefs` is present in the format (empty in test fixture — needs real story with Ink lists to exercise)

## Key Design Insights

### 1. JSONSerialization, not Codable
The format is a heterogeneous array where each element can be String, Int, Double, Array, Dict, or null. Swift's `Codable` cannot handle this without a fully custom `init(from:)` on every type. `JSONSerialization` → `Any` + a recursive classifier is the right approach.

### 2. Container encoding
A container is always a JSON array. The **last element** is special:
- `null` → no name, no flags, no named sub-containers
- `[String: Any]` → holds `#f` (flags), `#n` (name), and any named sub-containers as keys

The named-content dict and the flags dict are **the same object** — this is the key parsing invariant.

### 3. Float vs Int disambiguation
`JSONSerialization` returns `NSNumber` for both. Must check `NSNumber`'s underlying type (use `CFNumberGetType`) or compare `doubleValue == Double(intValue)` to distinguish ink `int` from `float`.

### 4. Native function set
The spec lists the common operators. The real fixture also contains `srnd` (SEED_RANDOM), confirming the set is larger than the spec documents. Must derive the complete list from inkjs source or C# runtime.

### 5. Walking order
Named sub-containers (from the last-element dict) are decoded separately from inline content items. The execution order of named content is determined at runtime by diverts/choice paths, not by declaration order in the JSON.

## Edge Cases to Handle Later
- `listDefs` with real Ink list definitions (not present in test fixture)
- Variable pointer values (`{"^var": "name", "ci": 0}`) — present in the JSON but only in complex choice expressions
- Read count references (`{"CNT?": "path"}`) — not present in test fixture but documented
- External function calls (`{"x()": "name", "exArgs": N}`) — not present in test fixture

## Performance
Not measured (not a goal of this spike). Parsing 146 nodes from a small JSON file is instantaneous.
