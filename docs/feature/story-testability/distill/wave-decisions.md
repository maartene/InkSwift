# Wave Decisions — story-testability DISTILL

**Wave**: DISTILL
**Feature**: story-testability
**Date**: 2026-06-10

---

## Prior Wave Reading

| Artifact | Status |
|---|---|
| `docs/product/journeys/story-author.yaml` | + read |
| `docs/product/architecture/brief.md` (story-testability section) | + read |
| `docs/product/kpi-contracts.yaml` | - not found (soft gate — warn, proceed) |
| `docs/feature/story-testability/discuss/user-stories.md` | + read |
| `docs/feature/story-testability/discuss/story-map.md` | + read |
| `docs/feature/story-testability/discuss/wave-decisions.md` | + read |
| `docs/feature/story-testability/design/wave-decisions.md` | + read |
| `docs/feature/story-testability/spike/` | - not present (no spike ran) |
| `docs/feature/story-testability/devops/` | - not present (no devops wave) |

---

## Wave-Decision Reconciliation

**Result**: 0 contradictions.

DISCUSS D-07 ("no new source files") was explicitly relaxed by the DESIGN wave to accommodate the `SwiftInkRuntimeTestSupport` SPM target — documented in `design/upstream-changes.md`. This is an acknowledged upstream change, not a contradiction.

DISCUSS D-04 (setVisitCount as public method on Story) was changed by DESIGN to Option C (separate `SwiftInkRuntimeTestSupport` target) — documented in `design/upstream-changes.md`. Same treatment.

---

## DWD-01: Walking Strategy — Strategy C (Real local)

**Decision**: Strategy C. All tests use real inklecate-compiled `.ink.json` fixtures from the test bundle via `Bundle.module.url(forResource:)`. No fakes, no in-memory doubles.

**Rationale**: This is a pure library with no costly external dependencies. Every prior feature in this codebase uses the same pattern (`Milestone6_MoveToKnotTests.swift`, `WalkingSkeletonTests.swift`). The driving port (`Story` facade) accepts a JSON string — a real fixture file is the correct real adapter.

**Tag**: `@real-io` on the walking skeleton scenario.

---

## DWD-02: Fixture — slice-story-testability.ink.json

**Decision**: New fixture compiled by inklecate from `slice-story-testability.ink`.

**Contents**:
- Variables: `score` (Int=0), `badge_awarded` (Bool=false), `player_name` (String="unnamed"), `has_key` (Bool=false)
- Knots: `start`, `score_setup`, `reward_check`, `locked_door`, `greeting`, `prologue`, `multi_line`, `with_choices`, `left`, `right`
- `reward_check`: block conditional `{ score >= 10: ... }` — exercises setVariable + getVariable post-execution
- `locked_door`: block conditional `{ has_key: ... }` — exercises Bool setVariable
- `greeting`: visit-count conditional `{ prologue > 1: ... }` — exercises setVisitCount
- `prologue`: has `#f:1` (CountVisits) — exercises visitCount read-back after natural navigation
- `multi_line`: three separate output lines — exercises continueMaximally drain
- `with_choices`: choice point — exercises continueMaximally stop-at-choice behaviour

**Rationale**: A dedicated fixture avoids coupling story-testability tests to the `slice-move-to-knot` fixture, which has different knot semantics. All engine features used (block conditionals, CNT? read counts, variable assignment, variable output) are confirmed IMPLEMENTED in the Feature Coverage Matrix.

---

## DWD-03: Scaffold Strategy — Stub Returns (RED, not BROKEN)

**Decision**: Scaffold methods on `Story` return empty/nil/zero values.

| Method | Return | Effect |
|---|---|---|
| `getVariable(_:)` | `nil` | Tests expecting non-nil values → RED |
| `setVariable(_:to:)` | (no-op) | Tests checking post-set state → RED |
| `visitCount(forKnot:)` | `0` | Tests expecting >0 → RED |
| `continueMaximally()` | `""` | Tests expecting content → RED |
| `setVisitCount(forKnot:to:)` | (no-op) | Tests checking injected counts → RED |

Tests whose acceptance criteria are satisfied by stub values (e.g. "unknown variable returns nil", "unknown knot returns 0") are green from the start — this is correct and expected.

**Confirmed**: 24 of 28 Milestone7 tests are RED. 4 are green (edge-case boundary checks that the stubs satisfy by construction).

---

## DWD-04: SwiftInkRuntimeTestSupport Target

**Decision**: Created `Sources/SwiftInkRuntimeTestSupport/StoryTestSupport.swift` as a redistributable SPM library with `@testable import SwiftInkRuntime`. Scaffold is a no-op extension.

**Package.swift changes**:
- New product: `SwiftInkRuntimeTestSupport`
- New library target: `SwiftInkRuntimeTestSupport` depending on `SwiftInkRuntime`
- `SwiftInkRuntimeTests` test target gains `SwiftInkRuntimeTestSupport` as a dependency

**Rationale**: Matches DESIGN ST-04 Option C. The `setVisitCount` method must be accessible to story authors in their own test suites, not just InkSwift's internal tests.

---

## Self-Review Checklist

- [x] 1. WS strategy declared in wave-decisions.md (DWD-01)
- [x] 2. WS scenarios tagged correctly (@real-io per Strategy C)
- [x] 3. Every driven adapter has at least one @real-io scenario (Story facade — `@real-io @driving_adapter` in Milestone7 header)
- [x] 4. N/A — no InMemory doubles used
- [x] 5. N/A — no container preference (Strategy C, all real local)
- [x] 6. Mandate 7: All methods imported in tests have scaffold files (Story.swift scaffold stubs + StoryTestSupport.swift scaffold)
- [x] 10. Driving adapter: `Story` facade is the driving port; all tests enter via `Story.getVariable`, `Story.setVariable`, etc. — not via InkEngine directly
- [x] 7. Mandate 7: Scaffolds include `// SCAFFOLD:` markers
- [x] 8. Mandate 7: Scaffold methods return wrong/empty values → tests fail (RED classification)
- [x] 9. Mandate 7: 24/28 tests RED, 4 green (edge-case boundary checks)
- [x] 11. F-001: N/A — Swift, not Python; all tests use real fixture JSON (no synthetic data)
- [x] 12-15: N/A — Swift Testing, not pytest-bdd
