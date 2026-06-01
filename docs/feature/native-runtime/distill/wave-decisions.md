# DISTILL Wave Decisions — native-runtime

**Wave**: DISTILL  
**Date**: 2026-06-01  
**Feature**: native-runtime  
**Upstream waves read**: SPIKE (DISCARD), DESIGN (complete), DEVOPS (missing — default matrix applied)

---

## DWD-01: Walking Skeleton Strategy — C (Real local)

**Chosen**: Strategy C. All acceptance tests use real adapters. No in-memory doubles, no fakes.

**Rationale**: `SwiftInkRuntime` is a pure Swift library with no paid APIs, no network, no costly externals. The only driven adapter is `InkDecoder` (reads a `Data` blob via `JSONSerialization`). Test fixtures are bundle resources (local filesystem). The oracle (`InkSwift.InkStory`) is in-process. No resource classification requires faking.

**Impact**: All scenarios tagged `@real-io`. The walking skeleton loads the real `test.ink.json` fixture from `Bundle.module`.

---

## DWD-02: DISCUSS Was Skipped — AC Derived from DESIGN

**Chosen**: Accept criteria derived from DESIGN wave-decisions.md section "Upstream Changes Flagged". No story-to-scenario traceability applied (no DISCUSS artifacts to trace).

**DESIGN-flagged items addressed in acceptance tests**:
1. Story initialisation and `canContinue` → WalkingSkeletonTests
2. Story continuation and `currentText` → WalkingSkeletonTests + Milestone2
3. Save/restore round-trip → Milestone3
4. Error cases (malformed JSON, unsupported version) → WalkingSkeletonTests + Milestone1
5. `listDefs` gap → deferred (no test fixture with Ink lists; noted in spike findings)
6. Tag retention policy → deferred (out of scope for initial native-runtime feature)

---

## DWD-03: Test Framework — XCTest (no Gherkin)

**Chosen**: XCTest with Given/When/Then comment structure in test methods. No Gherkin `.feature` files.

**Rationale**: Swift/SPM ecosystem uses XCTest. Quick/Nimble are optional BDD frameworks but not present in the project. Adding a BDD framework would be a new dependency. XCTest with descriptive method names and GWT comments achieves the same structure with zero new dependencies.

**Impact**: Acceptance tests are in `Tests/SwiftInkRuntimeTests/Acceptance/`. The `@walking_skeleton`, `@real-io`, `@skip` annotations appear as comments, not actual test annotations. Non-skeleton tests use `throw XCTSkip(...)` as the `@skip` mechanism.

---

## DWD-04: Adapter Coverage

| Adapter | @real-io scenario | Covered by |
|---------|-------------------|------------|
| InkDecoder (JSONSerialization boundary) | YES | WalkingSkeletonTests — loads real test.ink.json from bundle |

InkDecoder is the only driven adapter. It is exercised by every test that calls `Story.init(json:)`, since `InkDecoder` is the only path into the story from JSON.

---

## DWD-05: Deferred Items

- **listDefs**: No test fixture with real Ink list definitions. Tests for list variables deferred until a suitable `.ink.json` with lists is available.
- **Tag retention policy** (`retainTags` equivalent): API design deferred. DESIGN notes this is a configurable facade policy.
- **External function calls** (`x()` / `exArgs`): Not in test fixture. Deferred.
- **Variable pointer values** (`^var`): Not in test fixture. Deferred.
- **Read count references** (`CNT?`): Not in test fixture. Deferred.
