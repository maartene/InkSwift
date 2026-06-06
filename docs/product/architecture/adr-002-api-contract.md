# ADR-002: API Contract — Clean Redesign, Story Type Name, InkStory Frozen

**Status**: Accepted  
**Date**: 2026-06-01  
**Deciders**: Maarten Engels (project owner), Morgan (solution architect)  
**Feature**: native-runtime

---

## Context

The existing `InkSwift` module exposes `InkStory` as its public type. `InkStory` is tightly coupled to `JXKit` and inkjs: its observed-variable type is `JXValue`, its save format wraps a raw JS-engine JSON string, and its tag parsing is driven by JavaScript array results from `jxContext.eval(...)`.

Three questions must be resolved before designing the new module:

1. **Should `SwiftInkRuntime` wrap or extend `InkStory`?** If wrapping, the JXKit dependency would leak through the API surface or require an adapter layer.
2. **What is the public type name for the new module?** The name must be unambiguous at import sites and intuitive for Ink developers migrating from C# or inkjs.
3. **Should `InkStory.swift` be modified to share logic?** Any modification risks breaking the existing (stable) JS-bridge behaviour.

**Constraint from Decision 1**: `InkStory.swift` must not be touched. The JS-bridge module is frozen.

**Reference point**: The inkjs and C# ink runtime both expose `Story` as their primary type. The canonical usage pattern is `story.Continue()`.

---

## Decision

### 1. Clean redesign — no wrapping, no extending

`SwiftInkRuntime` is a completely new module with no imports from `InkSwift` in production code. The modules coexist as parallel library targets in the same SPM package.

### 2. Public type name: `Story`

The public facade type is named `Story` (in module `SwiftInkRuntime`). At import sites, the module name provides disambiguation: `import SwiftInkRuntime` makes `Story` available; `import InkSwift` makes `InkStory` available. A consumer using both writes `SwiftInkRuntime.Story` and `InkSwift.InkStory` to disambiguate.

`Story.continue()` mirrors C# `story.Continue()` and inkjs `story.Continue()` — the highest-familiarity name for the primary operation.

### 3. InkStory.swift is frozen — zero changes

No logic is extracted from `InkStory.swift` into shared utilities. Any apparent duplication (tag parsing, state serialization) is addressed by CREATE NEW in the reuse analysis (see `wave-decisions.md`).

---

## Alternatives Considered

### Alternative A: Rename and refactor InkStory into a protocol, have both implementations conform

Extracting a `PlayableStory` protocol from `InkStory` would require modifying `InkStory.swift` to conform to it. This violates the hard constraint (frozen module) and risks breaking existing consumers who depend on the current public API surface.

**Rejection rationale**: Hard constraint violation. Not viable.

### Alternative B: Name the new type `InkStory2` or `NativeStory`

Avoids the name collision with `InkStory` but produces an ugly, non-idiomatic API. Neither name communicates intent. `NativeStory` leaks an implementation detail (the "native vs JS" distinction) into the public API, which becomes meaningless if the JS-bridge module is eventually retired.

**Rejection rationale**: Poor developer experience. The module name (`SwiftInkRuntime`) is the right namespace for disambiguation, not the type name.

### Alternative C: Name the module `Ink` and the type `Story` (matching C# exactly)

Maximum familiarity for C# ink developers. However, `Ink` as a module name in an SPM package is likely to collide with future official Inkle Swift libraries and is too generic for a third-party package.

**Rejection rationale**: Collision risk with the `inkle` namespace outweighs the familiarity benefit. `SwiftInkRuntime` is scoped appropriately for a third-party OSS package.

---

## Consequences

**Positive**:
- `InkSwift` module is completely stable. Existing consumers are unaffected by the native-runtime branch.
- The `Story` API surface can be designed from scratch to match the inkjs/C# interface more closely than `InkStory` does.
- No JXKit types appear in the `SwiftInkRuntime` public API — consumers with no interest in JavaScript can depend on `SwiftInkRuntime` alone.
- Module-qualified disambiguation (`SwiftInkRuntime.Story`) is unambiguous and stable.

**Negative**:
- The tag-parsing logic (the `key: value` / bare-key split) is duplicated between `InkStory.swift` and `TagParser.swift` in the new module. This is a deliberate, bounded duplication: the logic is a pure function of ~10 lines, and sharing it would require either extracting it to a third module or touching `InkStory.swift`.
- Consumers wishing to migrate from `InkStory` to `Story` cannot use a drop-in replacement — the API surface differs. A migration guide will be needed when the module reaches stability.
