# ADR-003: State Serialization — Codable Format, No inkjs Compatibility

**Status**: Accepted  
**Date**: 2026-06-01  
**Deciders**: Maarten Engels (project owner), Morgan (solution architect)  
**Feature**: native-runtime

---

## Context

Ink story state must be persistable (save/restore for game save systems). Two serialization questions must be resolved:

1. **What format?** The C# ink runtime and inkjs use a JSON format for state that is specific to the JS/C# runtime internals (call stack frames, global store keys, etc.). This format is what `InkStory.stateToJSON()` stores inside its `SaveState.jsonState` field.
2. **Should the new module's state format be compatible with the inkjs format?** Compatibility would allow save files from the JS-bridge to be loaded by the native runtime, and vice versa.

**Constraints**:
- The inkjs state format is coupled to JavaScript execution model internals (the C# port maps naturally to the JS port). The `SwiftInkRuntime` execution model is a tree-walker with `StoryState` as a native Swift struct — the internal representation is structurally different.
- The existing `InkSwift.SaveState` format wraps the raw inkjs JSON string inside a second JSON envelope (with `currentTags`). It is not a documented public format; it is an implementation detail.
- Cross-format compatibility would require implementing a reader for the inkjs internal state JSON, which is undocumented and subject to change with inkjs releases. This creates an external integration risk with no corresponding benefit for the target use case (new projects using `SwiftInkRuntime` natively).

**Business driver**: The primary users of `SwiftInkRuntime` are new projects adopting the native module. Cross-format save compatibility is a convenience for projects migrating from the JS bridge — a secondary use case at this stage of the feature.

---

## Decision

`StoryState` is a Swift `struct` conforming to `Codable`. Its serialization format is defined entirely by its Swift properties and the standard `JSONEncoder`/`JSONDecoder` pair.

The format is explicitly **not compatible** with the inkjs state format. `Story.saveState()` returns `Data` (encoded `StoryState`); `Story.restoreState(_:)` accepts `Data`. The format is an implementation detail of `SwiftInkRuntime` — not a public contract.

`InkEngine` owns `var state: StoryState`. The facade exposes `saveState()` and `restoreState(_:)` as the only public entry points for persistence.

---

## Alternatives Considered

### Alternative A: Implement inkjs-compatible state serialization

Parse the inkjs internal state JSON and map it to/from `StoryState`. This would allow save files to be portable between the JS bridge and the native runtime.

**Evaluation**:
- The inkjs state format is not formally specified. It is reverse-engineered from the C# source. The format has changed between inkjs major versions.
- Implementing a reader requires mapping JS-runtime concepts (e.g., the `threads` array, `callstackThreads`, `storageMap` key format) to tree-walker concepts. These have no natural correspondence.
- Testing the mapping requires a corpus of real inkjs state files. No such corpus exists in the repository.
- The risk: a future inkjs update that changes the internal state format would silently corrupt saves loaded by the native runtime.

**Rejection rationale**: High implementation complexity, undocumented external dependency, and cross-version brittleness. The benefit (cross-runtime save portability) is not a stated requirement for the native-runtime feature.

### Alternative B: Store the entire ContainerNode tree in the save file (snapshot serialization)

Serialize the full parsed AST alongside the execution pointer and variable state. Restoring would deserialise the full tree, avoiding re-parsing the JSON story file.

**Evaluation**:
- Save files would be very large (the full story JSON is included).
- Restoring state already requires having the story loaded — the save file is always applied on top of a loaded story. The AST need not be included in the save.
- This is how neither inkjs nor the C# runtime works, making it non-idiomatic.

**Rejection rationale**: Bloated save files with no benefit. Correctly rejected as over-engineering.

### Alternative C: Use the same `SaveState` envelope as `InkSwift` (with a native payload)

Wrap the `StoryState` Codable JSON inside a `SaveState`-like struct that matches the `InkSwift.SaveState` key names (`jsonState`, `currentTags`).

**Evaluation**:
- Surface-level compatibility that breaks immediately when `jsonState` is decoded by an inkjs runtime (the content is not inkjs JSON).
- Naming imports a concept from the frozen module into the new module — an implicit coupling.

**Rejection rationale**: False compatibility promise. The key names match but the content is incompatible. This is worse than explicit incompatibility because it would cause silent failures.

---

## Consequences

**Positive**:
- `StoryState` Codable format is fully under the project's control. It can evolve as the tree-walker's internal representation evolves, with explicit versioning if needed.
- No dependency on the inkjs internal format or its versioning.
- `JSONEncoder`/`JSONDecoder` are standard Foundation types. No additional serialization library required.
- The save/restore API is minimal and testable: round-trip `saveState()` → `restoreState(_:)` is a straightforward property-based test.

**Negative**:
- Save files from `InkStory.stateToJSON()` cannot be loaded by `Story.restoreState(_:)`. A project migrating from the JS bridge must treat save files as incompatible and implement a migration strategy at the application layer.
- If inkjs state compatibility ever becomes a requirement, it must be implemented as a separate import adapter — not as a change to `StoryState` format.
