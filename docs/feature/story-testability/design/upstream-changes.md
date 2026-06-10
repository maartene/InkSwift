# Upstream Changes Notice — story-testability DESIGN Wave

**For review by**: Product Owner
**Date**: 2026-06-10
**Author**: Morgan (nw-solution-architect)
**Supersedes assumption in**: `docs/feature/story-testability/discuss/wave-decisions.md` § D-04

---

## Summary

One DISCUSS-wave assumption has been changed by the DESIGN wave. This notice describes what changed, why, and what impact it has on previously agreed acceptance criteria.

---

## Change: setVisitCount is Not a Plain Public Method

### What DISCUSS Assumed

DISCUSS D-04 and US-03 both assumed that `setVisitCount(forKnot:to:)` would be declared as a plain `public func` on the `Story` type in `Sources/SwiftInkRuntime/Facade/Story.swift`, symmetrically with `setVariable`. The US-03 acceptance criteria and slice-03 brief both list the signature as part of the `Story` public API surface.

### What DESIGN Decided

`setVisitCount(forKnot:to:)` is **not** added to the `SwiftInkRuntime` module public API. It does not appear in `Sources/SwiftInkRuntime/Facade/Story.swift`.

Instead, it is declared in a new redistributable SPM library target `SwiftInkRuntimeTestSupport`, in `Sources/SwiftInkRuntimeTestSupport/StoryTestSupport.swift`. This is Option C from three alternatives evaluated during the DESIGN wave.

Story authors use it by adding `SwiftInkRuntimeTestSupport` as a test dependency in their own `Package.swift`:

```swift
.testTarget(
    name: "MyStoryTests",
    dependencies: ["SwiftInkRuntime", "SwiftInkRuntimeTestSupport"]
)
```

The method signature in the test-support target:

```swift
// Sources/SwiftInkRuntimeTestSupport/StoryTestSupport.swift
// import SwiftInkRuntimeTestSupport in test targets
func setVisitCount(forKnot name: String, to count: Int)
```

### Rationale

The user explicitly stated during the DESIGN wave invocation:

> "Setting of knot visit count should be test only: its for testing purposes only."

A plain `public` method on `Story` is callable by any code that imports `SwiftInkRuntime` — including production app code. The user's constraint requires that the method be structurally unavailable in production contexts, not merely documented as "test-only."

Three options were evaluated:

| Option | Mechanism | Story author can use in own tests? | Production call possible? |
|---|---|---|---|
| A — `#if DEBUG` | Debug build flag | Yes (debug builds) | Yes, in debug builds |
| B — Test-target extension | Internal to `SwiftInkRuntimeTests` | No — not importable | No |
| C — `SwiftInkRuntimeTestSupport` target (chosen) | Separate SPM library | Yes — add as test dependency | Only via explicit misuse of Package.swift |

Option B was rejected because it only serves InkSwift's internal tests — story authors who depend on InkSwift as a package cannot import it. The feature's whole purpose is to enable story authors to write tests; Option B does not deliver that.

Option C was chosen because it is redistributable to story authors and provides a clean foundation for future test helpers (`assertOutput`, `setChoiceHistory`, etc.). The "only one method now" observation is not a reason to build the wrong structure.

### Impact on US-03 Acceptance Criteria

**Impact on WHAT is delivered**: None. All US-03 acceptance criteria describe behaviours — read-back, injection effectiveness, unknown-name handling — that remain fully testable. The `setVisitCount` behaviour described in the AC is identical regardless of which target declares the method.

**Impact on HOW story authors access the method**: Story authors add `SwiftInkRuntimeTestSupport` as a test dependency. This is one extra line in their `Package.swift` and one `import SwiftInkRuntimeTestSupport` in their test file. This is the standard Swift/SPM pattern for test-support libraries.

**Impact on visitCount (READ)**: None. `visitCount(forKnot:)` remains a plain `public func` on `Story`. The user only flagged the SET as test-only.

**Impact on Slice 03 implementation**: The crafter must:
1. Add `InkEngine.setVisitCount(forKnot:to:)` as an `internal` method
2. NOT add `Story.setVisitCount` to `Sources/SwiftInkRuntime/Facade/Story.swift`
3. Create `Sources/SwiftInkRuntimeTestSupport/StoryTestSupport.swift` with the `Story` extension (uses `@testable import SwiftInkRuntime`)
4. Update `Package.swift` to declare the `SwiftInkRuntimeTestSupport` library target and product

**Slice 03 tests**: The test examples in `slice-03-visit-counts.md` reference `story.setVisitCount(...)` — these calls remain valid because the test target imports `SwiftInkRuntimeTestSupport`.

---

## No Other Upstream Changes

All other DISCUSS decisions (D-02 through D-07) are unchanged and carried forward into DESIGN without modification. The three open questions (OQ-1, OQ-2, OQ-3) have been resolved in the DESIGN wave (see `wave-decisions.md`).
