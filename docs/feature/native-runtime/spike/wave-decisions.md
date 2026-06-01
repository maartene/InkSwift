# SPIKE Decisions — native-runtime

## Assumption Tested
Can we model the Ink JSON runtime format as Swift types and successfully decode a real `.ink.json` file into those types?

## Probe Verdict
WORKS: All 146 nodes in `test.ink.json` classified with zero unknowns. `JSONSerialization` + recursive walker handles the heterogeneous array format cleanly.

## Promotion Decision
**DISCARD** — findings are sufficient to inform DESIGN. No skeleton committed yet.

Rationale: The parsing question is answered. Before building the module skeleton, DESIGN should determine the full architecture of the `SwiftInkRuntime` module — specifically how the parsed AST feeds into a story execution engine. Building a skeleton now would lock in an AST shape before the execution model is designed.

## Design Implications for DESIGN wave

1. **JSONSerialization over Codable** — use `Any`-based deserialization with a recursive classifier function.
2. **Container is the central type** — everything else is an `InkObject` enum inside a `Container`. Start here.
3. **Module structure**: `SwiftInkRuntime` library target + `SwiftInkRuntimeTests` test target, both added to the existing `Package.swift`. No new dependencies required for parsing.
4. **Keep `InkSwift` unchanged** — it becomes the oracle for correctness comparison tests.
5. **Derive native function set from C# source** — the spec doc is incomplete (`srnd` is missing, likely others too).
6. **`listDefs` is a gap** — the test fixture has no Ink list definitions. A real story with lists must be used in later testing.

## Constraints Discovered
- The spec doc at `ink_JSON_runtime_format.md` lags the C# SSOT — always cross-check against `JsonSerialisation.cs`.
- `NSNumber` requires explicit int/float disambiguation (not self-evident from JSON alone).
- Named sub-containers and container flags share the same last-element dict object in the JSON array.
