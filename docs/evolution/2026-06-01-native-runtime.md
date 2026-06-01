# Evolution Document: native-runtime

**Date**: 2026-06-01
**Feature ID**: native-runtime
**Author**: Apex (nw-platform-architect)
**Status**: COMPLETE

---

## Feature Summary

SwiftInkRuntime is a pure-Swift tree-walker runtime for the Ink interactive fiction scripting language. It replaces the JavaScript bridge dependency (JXKit + ink-full.js) in the InkSwift Swift package with a native Swift implementation that carries zero external runtime dependencies beyond Foundation.

The module is a new Swift Package Manager library target added to the existing InkSwift package. It coexists with the frozen `InkSwift` target (the JS bridge) and is architecturally independent of it.

## Business Context

The InkSwift package previously required JXKit — a JavaScriptCore bridge — to execute Ink stories. This imposed:

- A JavaScript engine process on every platform that runs Ink stories
- An opaque JS runtime (ink-full.js) bundled into every application
- A hard dependency on JXKit's maintenance trajectory and platform support

SwiftInkRuntime eliminates all three constraints. Ink story execution is now a pure Swift in-process operation: no JS engine, no bundled JS, no JXKit. The module targets the same minimum platforms already required by InkSwift (macOS 10.15, iOS 13, tvOS 13) and introduces no new runtime dependencies.

The existing `InkSwift` / `InkStory` API is preserved and frozen. `SwiftInkRuntime` is an additive module — callers adopt it by importing `SwiftInkRuntime` and using `Story` instead of `InkStory`.

---

## Architecture Decisions

### Decision 1 — Clean Redesign (Module Strategy)

`InkStory` (the JS bridge) is frozen. Zero modifications were made to `InkStory.swift`. `SwiftInkRuntime` is a clean new module with no `import InkSwift` in any production source file.

Rationale: `InkStory` is coupled to `JXKit` at its API surface. Wrapping or extending it would drag the JavaScript engine dependency into the native module. The goal is a JS-free module; wrapping defeats that entirely.

### Decision 2a — Three-Layer Architecture with Enforced Boundaries

The module is structured as three source layers:

| Layer | Directory | Permitted imports |
|-------|-----------|-------------------|
| Decoder | `Sources/SwiftInkRuntime/Decoder/` | Foundation only |
| Engine | `Sources/SwiftInkRuntime/Engine/` | Decoder layer types |
| Facade | `Sources/SwiftInkRuntime/Facade/` | Engine and Decoder layer types |

Three mechanical rules enforced throughout implementation:
- **R1**: Dependency direction is strictly Facade → Engine → Decoder. No reverse imports.
- **R2**: `NodeKind` is `internal`. It never becomes `public`.
- **R3**: `JSONSerialization` is only called from `Decoder/` files.

### Decision 2b — Test-Only Oracle Import

The test target (`SwiftInkRuntimeTests`) imports `InkSwift` to use `InkStory` as a correctness oracle. An oracle comparison test drives both the JS bridge and the native runtime against the same `.ink.json` fixture and asserts line-by-line output equality.

### Decision 3 — Tree-Walker Execution Model

`TreeWalker` recursively visits `ContainerNode` and dispatches on `NodeKind`. Control flow is modelled as pointer updates within `StoryState`. Every step is a named Swift function call; state is inspectable as a plain struct at any point.

Alternatives rejected: A bytecode interpreter would require a compilation pass and a separate VM; too complex for the initial implementation scope. A direct port of inkjs would import JavaScript execution semantics into Swift, conflating two very different models.

The spike (DISCARD verdict, findings promoted to DESIGN) confirmed feasibility: all 146 nodes in the real test fixture were classified with zero unknowns.

### Decision 4 — Codable State Serialization

`StoryState` is a Swift `struct` conforming to `Codable`. The format is defined entirely by its Swift properties. No compatibility with the inkjs internal state format was attempted.

Rationale: The inkjs state format is undocumented and coupled to JavaScript execution internals. Implementing a reader for it would introduce an external dependency on an undocumented format outside the feature scope.

### Decision 5 — Engine Owns State

`InkEngine` (a `final class`) owns `var state: StoryState`. It exposes `saveState() -> Data` and `restoreState(_ data: Data) throws`. `Story` (the facade) is a pure delegation layer with no state of its own.

### Decision 6 — Public Type Named `Story`

The public facade type is `Story` in module `SwiftInkRuntime`. `Story.continue()` mirrors the C# and inkjs APIs exactly, giving Ink developers an immediately familiar method name.

---

## Steps Completed

Delivery executed via Outside-In TDD across 12 roadmap steps in 3 milestones.

### Milestone 1 — JSON Decoding (Steps 01-01 through 01-04)

Implemented the Decoder layer:

- **01-01**: `NodeKind` enum with all 14 node types (text, newline, intValue, floatValue, controlCommand, nativeFunction, divert, choicePoint, variableAssignment, variableReference, tagOpen, tagClose, voidValue, container). Declared `internal`.
- **01-02**: `ContainerNode` struct and `InkDecoder.decode(_:)` recursive parser. Handles the container invariant: last-element null = no metadata; last-element dict = flags + named sub-containers. Integers and floats correctly disambiguated via `NSNumber` type check.
- **01-03**: `InkDecoder.probe()` and `Story.init(json:)` wiring. Walking skeleton acceptance tests green: story loads from real fixture with `canContinue == true`; malformed JSON throws `StoryError.invalidJSON`.
- **01-04**: All 6 Milestone 1 acceptance tests enabled and green. No new production code required — correctness carried forward from 01-02 and 01-03.

### Milestone 2 — Story Execution (Steps 02-01 through 02-05)

Implemented the Engine layer and wired the Facade:

- **02-01**: `TagParser.parse(_:)` — pure function, no Foundation imports. Splits on first colon, returns (key, optional value).
- **02-02**: `StoryState` struct with full field set: current pointer (container path + index), call stack, visit counts, output stream buffer, variables state, current tags, and `isEnded` flag. Codable conformance declared.
- **02-03**: `TreeWalker.step(in:state:)` — recursive visitor dispatching on all NodeKind cases. Text accumulation, newline flushing, control command handling, divert resolution, choice point registration, tag accumulation.
- **02-04**: `InkEngine` orchestrator — drives `TreeWalker`, exposes all computed properties, implements `chooseChoice(at:)`, `saveState()`, `restoreState(_:)`.
- **02-05**: `Story` facade wired to `InkEngine`. All 7 Milestone 2 acceptance tests green, including the oracle comparison test (output matches `InkStory` line-by-line for the real fixture).

### Milestone 3 — Save and Restore (Steps 03-01 through 03-03)

- **03-01**: Verified `StoryState` Codable round-trip at a mid-story point. No new production code required — conformance was complete from Phase 2.
- **03-02**: `InkEngine.saveState()` and `restoreState(_:)` implemented. Throws `StoryError.invalidStateData` for undecodable input.
- **03-03**: `Story` facade save/restore wired. All 4 Milestone 3 acceptance tests green. Full test suite: 49 tests (unit + acceptance), all passing.

### Post-Milestone Quality Passes

- **L1-L4 refactoring**: 4 commits (235c7be, 7f52434, 9ac9599, f536d83) applied after Milestone 3. All tests remained green throughout.
- **Adversarial review**: 1 revision pass. Issues fixed: tautological tag test replaced with a distinct assertion; pointer state assertion strengthened.
- **Mutation testing**: SKIPPED — Muter is not reliable for Swift in this project.

---

## Issues Encountered

### Anonymous Sub-Container Descent

Ink's JSON format nests containers inside containers without explicit index references. The tree-walker must descend into anonymous child containers as part of the main sequence — not just via named divert targets. The initial implementation treated all child containers as reachable only through diverts, which caused the walker to skip inline nested sequences entirely.

Resolution: `TreeWalker` was updated to automatically descend into anonymous `container` nodes encountered during sequential traversal, pushing a frame onto the call stack and continuing from child index 0.

### Choice Target Path Resolution

Divert targets for choice continuations are stored as path strings (e.g., `"0.1.c"`) in the Ink JSON. The path resolution logic initially only handled absolute paths from the root container. Relative paths (common for choices within a knot) were resolved incorrectly.

Resolution: Path resolution was refactored to resolve relative paths against the current container context before falling back to absolute root resolution.

### Empty Line Skipping

The oracle comparison test revealed that the native runtime was emitting blank lines that `InkStory` suppresses. Ink emits a `\n` node after control commands in some contexts; these produce empty output lines if not filtered.

Resolution: `InkEngine`'s line-flushing logic was updated to discard lines consisting only of whitespace, matching the JS bridge's behaviour.

### ContainerStackFrame Serialization for Nested Containers

`StoryState.Codable` conformance failed at runtime when the call stack contained frames referencing deeply nested containers. The container path encoding (a sequence of indices from the root) did not correctly reconstruct the container reference on decode because the root container reference itself was not stored — only the path was.

Resolution: `ContainerStackFrame` was redesigned to store the full path from the root as a `[String]` array (mixing integer index strings with named sub-container keys), and `InkEngine.restoreState(_:)` was updated to resolve this path against the decoded root container before resuming execution.

---

## Lessons Learned

1. **The oracle test is the most valuable test.** The line-by-line comparison against `InkStory` caught issues (empty line skipping, path resolution) that no unit test specification could have anticipated without first understanding the JS bridge's exact behaviour. Write the oracle test first, before the implementation is complete.

2. **The Ink JSON format has invisible invariants.** The spec document lags the C# source of truth. Several container encoding decisions (integer/float disambiguation, anonymous container descent, choice path encoding) were discoverable only by reading `JsonSerialisation.cs` directly. Always cross-check the spec against the C# SSOT.

3. **Path-based state serialization requires round-trip discipline.** Storing a pointer as a path (not a reference) means the decode path must be tested against a live container tree — not just validated as a type. Unit tests that only verify Codable conformance structurally will miss runtime resolution failures. Test decode + resume, not just decode.

4. **Frozen boundaries protect scope.** The `InkStory.swift` freeze constraint prevented scope creep throughout delivery. Every "could we just add this to InkStory" question was immediately closed. Without a hard constraint, the delivery scope would have expanded toward a hybrid implementation.

5. **Refactoring gates should come after full milestone green.** The L1-L4 refactoring pass after Milestone 3 was cleaner than refactoring per-step because all acceptance tests were available as a safety net. Per-step refactoring with a partial test suite risks breaking behaviour that is only verified by later tests.

---

## Deferred Items

The following items were identified during delivery but are out of scope for this iteration:

- **Ink list variables** (`listDefs`): The test fixture has no Ink list definitions. A story with lists is needed to drive this feature.
- **Tag retention policy** (`retainTags` equivalent): Whether `Story` should expose a configurable tag retention list (as `InkStory` does via `retainTags: ["IMAGE"]`) is deferred.
- **External function calls** (`x()` / `exArgs`): Not present in the test fixture.
- **Variable pointer values** (`^var`) and read count references (`CNT?`): Not present in the test fixture.

---

## Permanent Code Location

- `Sources/SwiftInkRuntime/Decoder/` — NodeKind, ContainerNode, InkDecoder
- `Sources/SwiftInkRuntime/Engine/` — TagParser, StoryState, TreeWalker, InkEngine
- `Sources/SwiftInkRuntime/Facade/` — Story (public facade)
- `Tests/SwiftInkRuntimeTests/Acceptance/` — WalkingSkeletonTests, Milestone1-3 acceptance tests
