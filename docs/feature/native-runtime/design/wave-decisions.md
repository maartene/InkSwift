# DESIGN Wave Decisions — native-runtime

**Wave**: DESIGN  
**Date**: 2026-06-01  
**Architect**: Morgan (nw-solution-architect)  
**Mode**: Guide (collaborative, decision-by-decision)  
**Upstream wave**: DISCUSS was skipped — see flag section below.

---

## All Six Decisions

### Decision 1 — Module Strategy: Clean Redesign

**Chosen**: Clean redesign. `InkStory` (JS bridge) is frozen — zero changes to `InkStory.swift`. The new module is named `SwiftInkRuntime`. No `import InkSwift` appears in production code of `SwiftInkRuntime`.

**Rationale**: `InkStory` is coupled to `JXKit` (`JXValue`, `JXContext`) at its API surface. Wrapping or extending it would drag the JavaScript engine dependency into the native module's public interface. The goal of the native module is to be JS-free; wrapping defeats that entirely.

**Alternative rejected**: Extending `InkStory` with a "native mode" toggle — rejected because it would require modifying the frozen file and would conflate two fundamentally different execution models in one class.

---

### Decision 2a — Enforced Layers

**Chosen**: Three source layers with mechanical boundary rules:

| Layer | Permitted imports |
|-------|-----------------|
| `Decoder/` | Foundation only |
| `Engine/` | `Decoder/` layer types |
| `Facade/` | `Engine/` and `Decoder/` layer types |

Three mechanical rules:
- **R1**: Dependency direction is strictly Facade → Engine → Decoder. No reverse imports.
- **R2**: `NodeKind` enum is `internal`. It never becomes `public`.
- **R3**: `JSONSerialization` is only called from `Decoder/` files.

**Rationale**: Prevents the accretion of cross-layer coupling that has historically made `InkStory` hard to test in isolation. The spike showed that `JSONSerialization` and the node classification logic are a natural seam — keeping them isolated protects the engine from JSON-parsing concerns.

---

### Decision 2b — Test-Only Oracle Import

**Chosen**: `SwiftInkRuntimeTests` test target may `import InkSwift` to use `InkStory` as a correctness oracle. This is test infrastructure only — zero production code crosses module boundaries.

**Rationale**: The JS-bridge is the ground truth for Ink output. Driving both implementations against the same `.ink.json` fixture and asserting line-by-line output equality is the most direct way to verify correctness during the native runtime's development. No alternative provides equivalent confidence at comparable cost.

---

### Decision 3 — Execution Model: Tree-Walker

**Chosen**: Tree-walker execution model. `TreeWalker` recursively visits `ContainerNode` and dispatches on `NodeKind`. Control flow is modelled as pointer updates within `StoryState`.

**Rationale**: Debuggability and expandability are the primary drivers. Every step is a named Swift function call; state is inspectable as a plain struct at any point. The spike proved the model is feasible — 146 nodes in the real fixture were classified with zero unknowns using a recursive visitor.

**See**: [ADR-001](../../product/architecture/adr-001-execution-model.md) for full alternatives analysis.

---

### Decision 4 — State Serialization: New Codable Format

**Chosen**: `StoryState` is a Swift `struct` conforming to `Codable`. The format is defined by its Swift properties. No inkjs state format compatibility.

**Rationale**: The inkjs internal state format is undocumented, coupled to JavaScript execution model internals, and subject to change with inkjs releases. Implementing a reader for it introduces an external dependency on an undocumented format with no corresponding requirement in scope.

**See**: [ADR-003](../../product/architecture/adr-003-state-serialization.md) for full alternatives analysis.

---

### Decision 5 — State Ownership

**Chosen**: `final class InkEngine` owns `var state: StoryState` (struct, Codable). Engine exposes `saveState() -> Data` and `restoreState(_ data: Data) throws`. The `Story` facade wraps these calls.

**Rationale**: Centralising state in a single owner (the engine) eliminates the risk of state divergence between the facade and the engine. The facade is a pure delegation layer with no state of its own. This maps cleanly to the ports-and-adapters pattern: the engine is the application core; the facade is the primary driving port.

---

### Decision 6 — Public Type Name: Story

**Chosen**: The public facade type is named `Story` (in module `SwiftInkRuntime`).

**Rationale**: `Story.continue()` mirrors C# `story.Continue()` and inkjs `story.Continue()` exactly. Ink developers migrating from either runtime will find the method name immediately familiar. The module name `SwiftInkRuntime` provides the namespace disambiguation at import sites (`SwiftInkRuntime.Story` vs `InkSwift.InkStory`).

**See**: [ADR-002](../../product/architecture/adr-002-api-contract.md) for alternatives analysis.

---

## Mandatory Reuse Analysis

Examined: `/Users/maartene/Developer/Swift/InkSwift/Sources/InkSwift/InkStory.swift`  
Constraint: `InkStory.swift` must not be touched.

| Existing component | Location | Overlap with new module | Decision | Justification |
|-------------------|----------|------------------------|----------|---------------|
| `Option` struct | `InkStory.swift` lines 479-492 | Represents a player choice — same concept as what `SwiftInkRuntime` needs for `currentChoices` | **CREATE NEW** | `Option` has a `fileprivate init` — it cannot be instantiated outside `InkStory.swift`. Its `tags` field type is `[String: String]`, which matches, but it is tied to the `InkSwift` module namespace. Extracting it would require either moving it to a shared module (new dependency) or copying it. Copying is the only viable path given the frozen constraint. The type is ~10 lines. |
| `SaveState` struct | `InkStory.swift` lines 22-25 | Persists story state — same intent as `StoryState` in new module | **CREATE NEW** | `SaveState` is a `private` nested struct inside `InkStory`. It cannot be accessed outside the class. Its payload (`jsonState: String`) is inkjs engine JSON — structurally incompatible with the tree-walker's native state. Even if accessible, the format is wrong. `StoryState` must be a new Codable struct with completely different fields. |
| Tag parsing (`parseTags`, `refreshOptions`) | `InkStory.swift` lines 284-312, 209-245 | Parses `"key: value"` and bare-key tag strings into `[String: String]` — same format, same algorithm | **CREATE NEW** | The parsing logic is 15-20 lines of pure string manipulation. It is embedded in private methods of `InkStory` — not extractable without modifying the frozen file. Duplication is deliberate and bounded. The new `TagParser` in `Engine/` is a pure function; it has no coupling to `InkStory`. If the tag format ever changes in the Ink spec, both parsers will need updating independently — this is acceptable given the size of the logic. |
| `currentTags` / `globalTags` logic | `InkStory.swift` lines 285-311 | Maintains retained-tag semantics (`retainTags` list) and dictionary merge — same concept needed in `StoryState` | **CREATE NEW** | `retainTags` (the "IMAGE" retention feature) is an `InkStory`-specific UX decision, not a core Ink spec requirement. `SwiftInkRuntime` will implement tag retention as a configurable policy on `Story` (the facade), independently. The underlying tag dictionary management is a few lines; no meaningful reuse is possible without touching the frozen file. |

**Summary**: All four overlapping concerns require CREATE NEW. None can be extended or imported without either modifying `InkStory.swift` (forbidden) or creating a third shared module that would be a premature abstraction for ~50 lines of logic total.

---

## Technology Stack

| Component | Choice | Version | License | Role |
|-----------|--------|---------|---------|------|
| Swift | SPM module | 5.8+ | Apache 2.0 | Language and build system |
| Foundation | System | Bundled | Apple APSL | `JSONSerialization`, `Codable`, `Data` |
| JXKit | Existing dependency | 3.x | MIT | Used by frozen `InkSwift` only — not a dependency of `SwiftInkRuntime` |
| XCTest | System | Bundled | Apple | Test framework |
| SwiftLint | Dev tool | 0.55+ | MIT | Architectural boundary enforcement (R1, R3) |

No new runtime dependencies are introduced by `SwiftInkRuntime`.

---

## Constraints Established

| Constraint | Source | Impact |
|-----------|--------|--------|
| `InkStory.swift` must not be touched | Decision 1 | All overlapping logic must be created new in `SwiftInkRuntime` |
| No `import InkSwift` in production code | Decision 1 | Oracle pattern restricted to test targets only |
| `JSONSerialization` only in `Decoder/` | Decision 2a / Rule R3 | Decoder layer is the sole JSON parsing boundary |
| `NodeKind` must remain `internal` | Decision 2a / Rule R2 | Node kinds are an implementation detail — never exposed to callers |
| No inkjs state format compatibility | Decision 4 | Save files from `InkStory` cannot be loaded by `Story` |
| No new runtime dependencies | Technology stack | `SwiftInkRuntime` builds with Foundation only |
| Minimum platform targets inherited from `Package.swift` | Existing | macOS 10.15, iOS 13, tvOS 13 |

---

## Upstream Changes Flagged (DISCUSS Wave Skipped)

The DISCUSS wave was skipped for this feature. The following items would normally be owned by user stories and acceptance criteria from DISCUSS. They are flagged here for the acceptance-designer (DISTILL wave) to address:

1. **No formal user stories exist** for `SwiftInkRuntime`. The feature is developer-facing (a library, not an end-user product), but acceptance criteria should still be written in observable, behavioural terms. Suggested stories:
   - "As a Swift developer, when I call `Story(json:)` with a valid `.ink.json` string, the story initialises and `canContinue` is `true`."
   - "As a Swift developer, when I call `story.continue()` on a loaded story, `currentText` returns the next line of content."
   - "As a Swift developer, when I call `story.saveState()` and then `story.restoreState(_:)` on a new instance loaded from the same story, the story continues from the saved position."

2. **No acceptance criteria for error cases**: What should `Story(json:)` throw for malformed JSON? For an unsupported ink version? These are design decisions that currently live only in the architecture document (via the probe requirement). DISTILL should formalise them.

3. **`listDefs` is a known gap**: The spike found no Ink list definitions in the test fixture. Behaviour of the tree-walker when encountering `listDefs` is not specified. A user story covering Ink list variables should be added before the feature is considered complete.

4. **Tag retention policy (`retainTags`)**: `InkStory` exposes a `retainTags: [String]` property (default: `["IMAGE"]`). Whether `Story` should expose an equivalent is an API design decision that should be captured in a user story. The architecture document currently defers this to the facade design.
