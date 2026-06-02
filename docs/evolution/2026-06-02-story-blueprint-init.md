# Evolution: story-blueprint-init

**Date**: 2026-06-02
**Branch**: native-runtime
**Feature**: Two-step Story initializer (JSON -> StoryBlueprint -> Story)

---

## Business Context

JSON parsing in Swift can be slow for large Ink story files. The existing
`Story.init(json:)` parses the full JSON on every instantiation, meaning
applications that create multiple `Story` instances from the same JSON source
pay the parse cost repeatedly.

The parse-once, reuse-many pattern solves this: parse once into a
`StoryBlueprint`, then instantiate any number of `Story` objects from that
blueprint at near-zero cost. This is particularly valuable for game engines and
apps that reset stories frequently (e.g., player restarts a chapter, A/B
testing different story paths from the same source).

---

## Steps Completed

| Step | Name | Outcome |
|------|------|---------|
| 01-01 | Create StoryBlueprint with init(json:) and unit tests | PASS |
| 01-02 | Add Story.init(blueprint:) and refactor Story.init(json:) as convenience wrapper | PASS |
| 02-01 | Verify all existing tests remain green after the refactor | PASS — 55/55 |

### Step 01-01: StoryBlueprint type

Introduced `Sources/SwiftInkRuntime/Facade/StoryBlueprint.swift`. The new
public struct wraps an internal `ContainerNode` resulting from
`InkDecoder.probe()` + `InkDecoder.decode()`. It surfaces the same
`StoryError` variants as `Story.init(json:)`. No `JSONSerialization` call
appears in the Facade layer (architecture rule R3 respected).

Acceptance test drove three behaviours: valid JSON returns blueprint, invalid
JSON throws `StoryError.invalidJSON`, unsupported inkVersion throws
`StoryError.unsupportedInkVersion`. The fourth behaviour (probe fixture
failure, B4) has no injection seam — consistent with the existing
`Story.init(json:)` pattern — so unit decomposition was not applicable.

### Step 01-02: Story.init(blueprint:) and convenience wrapper

Added `Story.init(blueprint: StoryBlueprint) throws` as the designated
initialiser. It initialises `InkEngine` directly from the `ContainerNode` held
in the blueprint and does NOT call `InkDecoder.probe()` again — no redundant
validation per the accepted design decision.

`Story.init(json:)` was refactored into a convenience initialiser that
delegates to `StoryBlueprint.init(json:)` then `Story.init(blueprint:)`,
preserving full backwards compatibility. `Story` remains a `final class`; the
Swift designated/convenience initialiser constraint made `Story.init(blueprint:)`
the single designated initialiser by necessity.

Acceptance tests verified: two `Story` instances from the same blueprint
produce identical independent output when continued; `Story.init(json:)` is
behaviourally equivalent to the blueprint path.

### Step 02-01: Regression gate

Full `SwiftInkRuntimeTests` suite executed: 55/55 tests passed. Covered test
groups: `WalkingSkeletonTests`, `Milestone1_JSONDecodingTests`,
`Milestone2_StoryExecutionTests`, `Milestone3_SaveRestoreTests`. No
modifications to any pre-existing test file were required.

---

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| `StoryBlueprint` is a `public struct` wrapping an `internal ContainerNode` | Structs have value semantics suitable for a parsed, immutable snapshot; `ContainerNode` remains an implementation detail (R1) |
| `Story.init(blueprint:)` is the designated initialiser | Swift requires convenience initialisers to call a designated init on the same class; blueprint path is the canonical construction path |
| `Story.init(json:)` is a convenience wrapper | Preserves public API backwards compatibility at zero cost |
| No redundant `probe()` in `Story.init(blueprint:)` | Blueprint constructor already validated the JSON; re-running probe would negate the parse-once benefit |
| Unit RED skipped where acceptance tests cover all boundaries | Acceptance tests at the Story driving port already covered B5, B6, B7 — no additional unit decomposition added value |

---

## Results

- Test suite: 55/55 PASS
- Architecture rules R1 (internal/public boundary) and R3 (no JSONSerialization in Facade) respected
- Adversarial review by solution-architect-reviewer: APPROVED (2026-06-02)
- No breaking changes to public API

---

## Source Files

- `docs/feature/story-blueprint-init/deliver/roadmap.json` — accepted roadmap with 3 steps across 2 phases
- `docs/feature/story-blueprint-init/deliver/execution-log.json` — step-by-step TDD execution record (schema v3.0)

## Implementation Files

- `Sources/SwiftInkRuntime/Facade/StoryBlueprint.swift` — new public type
- `Sources/SwiftInkRuntime/Facade/Story.swift` — refactored designated/convenience initialisers
- `Tests/SwiftInkRuntimeTests/Unit/StoryBlueprintTests.swift` — unit and acceptance tests for the blueprint path
